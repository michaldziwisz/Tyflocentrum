import Foundation
import SwiftUI
@testable import Tyflocentrum
import UIKit
import XCTest

@MainActor
final class ContentTimeIntegrationTests: XCTestCase {
	override func tearDown() {
		StubURLProtocol.requestHandler = nil
		super.tearDown()
	}

	private func session() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: config)
	}

	func testOptionalGarbageDoesNotBreakSummaryDetailOrOldCache() throws {
		for optional in ["", #", "tyflocentrum":null"#, #", "tyflocentrum":false"#, #", "tyflocentrum":[]"#, #", "tyflocentrum":{"schema_version":1,"audio_status":"ready","duration_seconds":true}, "modified_gmt":42"#] {
			let raw = #"{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test"},"excerpt":{"rendered":"Opis"},"content":{"rendered":"Pełna treść"},"guid":{"rendered":"https://tyflopodcast.net/?p=1"},"link":"https://tyflopodcast.net/?p=1""# + optional + "}"
			let data = Data(raw.utf8)
			let summary = try JSONDecoder().decode(WPPostSummary.self, from: data)
			let detail = try JSONDecoder().decode(Podcast.self, from: data)
			XCTAssertEqual(detail.content.rendered, "Pełna treść")
			XCTAssertEqual(summary.asPodcastStub().id, 1)
			XCTAssertEqual(summary.tyflocentrum?.audioTime ?? .unavailable, .unavailable)
			let cached = try JSONDecoder().decode([WPPostSummary].self, from: JSONEncoder().encode([summary]))
			XCTAssertEqual(cached.map(\.id), [1])
		}
	}

	func testFavoritesPreserveOldIDsOrderAndOptionalData() throws {
		let raw = #"[{"type":"podcast","summary":{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Dawny podcast"},"link":"https://tyflopodcast.net/?p=1"}},{"type":"article","origin":"page","summary":{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Dawny artykuł"},"link":"https://tyfloswiat.pl/czasopismo/numer/artykul/"}},{"type":"article","origin":"page","summary":{"id":2,"date":"2026-01-20T00:59:40","title":{"rendered":"Numer"},"link":"https://tyfloswiat.pl/czasopismo/tyfloswiat-4-2025/"}}]"#
		let defaults = UserDefaults(suiteName: "ContentTime.\(UUID().uuidString)")!
		defer { defaults.removeObject(forKey: "test") }
		defaults.set(Data(raw.utf8), forKey: "test")
		let store = FavoritesStore(userDefaults: defaults, storageKey: "test")
		XCTAssertEqual(store.items.map(\.id), ["podcast.1", "article.page.1", "article.page.2"])
		XCTAssertEqual(store.items.compactMap(\.contentTimeRequest).map(\.key), [ContentTimeKey(kind: .podcast, id: 1), ContentTimeKey(kind: .pages, id: 1)])
		let reloaded = try JSONDecoder().decode([FavoriteItem].self, from: JSONEncoder().encode(store.items))
		XCTAssertEqual(reloaded.map(\.id), store.items.map(\.id))
	}

	private actor Gate {
		var continuation: CheckedContinuation<Void, Never>?
		var started = false
		func block() async { started = true; await withCheckedContinuation { continuation = $0 } }
		func release() { continuation?.resume(); continuation = nil }
	}

	private final class Registry: @unchecked Sendable {
		private let lock = NSLock()
		private var stored: [URL] = []
		func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; stored.append(url) }
		var urls: [URL] { lock.lock(); defer { lock.unlock() }; return stored }
	}

	func testRealFeedAndDetailAvailableWhileMetadataBlockedAndURLRegistryIsLight() async throws {
		let urls = Registry()
		StubURLProtocol.requestHandler = { request in
			let url = try XCTUnwrap(request.url)
			urls.append(url)
			let detail = Int(url.lastPathComponent) != nil
			let item = #"{"id":1,"date":"2026-01-20T00:59:40","title":{"rendered":"Test"},"excerpt":{"rendered":"Opis"},"content":{"rendered":"Czytelny artykuł"},"guid":{"rendered":"https://tyfloswiat.pl/?p=1"},"link":"https://tyfloswiat.pl/?p=1","tyflocentrum":false}"#
			return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data((detail ? item : "[\(item)]").utf8))
		}
		let gate = Gate()
		let client = ContentTimeClient(transport: { request in
			await gate.block()
			return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
		})
		let api = TyfloAPI(session: session(), contentTimeClient: client)
		let model = PostSummariesFeedViewModel()
		// Nawet aktywne pobranie metadanych nie zajmuje transportu listy.
		let pending = Task { await client.fetch([ContentTimeKey(kind: .posts, id: 1)]) }
		while !(await gate.started) {
			await Task.yield()
		}
		await model.loadIfNeeded { page, count in try await api.fetchArticleSummariesPage(page: page, perPage: count) }
		XCTAssertEqual(model.items.map(\.id), [1])
		XCTAssertFalse(model.isLoading)
		XCTAssertNil(model.errorMessage)
		for url in urls.urls {
			XCTAssertEqual(url.path, "/wp-json/wp/v2/posts")
			let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "_fields" }?.value ?? ""
			XCTAssertTrue(fields.contains("tyflocentrum"))
			XCTAssertFalse(fields.split(separator: ",").contains("content"))
			XCTAssertFalse(url.absoluteString.contains("pobierz.php"))
		}
		let article = try await api.fetchArticle(id: 1)
		XCTAssertEqual(article.content.rendered, "Czytelny artykuł")
		XCTAssertEqual(api.getListenableURL(for: article).path, "/pobierz.php")
		XCTAssertFalse(urls.urls.contains { $0.path == "/pobierz.php" })
		await gate.release()
		let result = await pending.value
		XCTAssertTrue(result.isEmpty)
	}

	private struct ValuesProbe: View {
		@Environment(\.contentTimeValues) private var values
		let observe: ([ContentTimeKey: ContentTimeLabel]) -> Void

		var body: some View {
			Color.clear.onChange(of: values, initial: true) { _, current in observe(current) }
		}
	}

	func testLongListModifierDeliversEveryTimeWithBoundedCache() async throws {
		let urls = Registry()
		let client = ContentTimeClient(transport: { request in
			let url = try XCTUnwrap(request.url)
			urls.append(url)
			let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
			let ids = try XCTUnwrap(query.first { $0.name == "ids" }?.value).split(separator: ",").compactMap { Int($0) }
			let now = ISO8601DateFormatter().string(from: Date())
			let items: [[String: Any]] = ids.map { id in
				["id": id, "freshness": "fresh", "checked_at": now,
				 "tyflocentrum": ["schema_version": 1, "text_status": "ready", "word_count": 1001, "reading_minutes": 6]]
			}
			let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "source": "tyfloswiat.pl", "type": "posts", "items": items])
			return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let requests = (1 ... 600).reversed().map { id in
			ContentTimeRequest(WPPostSummary(id: id, date: "", title: .init(rendered: "Artykuł \(id)"), link: "https://tyfloswiat.pl/?p=\(id)"), kind: .posts)
		}
		let ready = expectation(description: "Rzeczywisty modyfikator SwiftUI przekazał wszystkie 600 czasów")
		ready.assertForOverFulfill = false
		var observed: [ContentTimeKey: ContentTimeLabel] = [:]
		let root = ValuesProbe { values in
			observed = values
			if requests.allSatisfy({ values[$0.key] == .reading(6) }) { ready.fulfill() }
		}
		.contentTimes(requests)
		.environmentObject(TyfloAPI(session: session(), contentTimeClient: client))
		let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
		let window = UIWindow(windowScene: scene)
		window.frame = scene.coordinateSpace.bounds
		window.rootViewController = UIHostingController(rootView: root)
		window.isHidden = false
		defer { window.isHidden = true; window.rootViewController = nil }
		await fulfillment(of: [ready], timeout: 10)
		XCTAssertEqual(observed.values.filter { $0 == .reading(6) }.count, requests.count)
		XCTAssertTrue(requests.allSatisfy { observed[$0.key] == .reading(6) })
		let cached = await client.cachedCount
		XCTAssertLessThanOrEqual(cached, 512)
		XCTAssertEqual(urls.urls.count, (requests.count + 49) / 50)
		for url in urls.urls {
			let ids = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value).split(separator: ",")
			XCTAssertLessThanOrEqual(ids.count, 50)
			XCTAssertEqual(url.path, "/v1/metadata")
		}
	}

	func testListStateDiscardsOldRefreshCallbackAndExpiresValues() async throws {
		let gate = Gate()
		let client = ContentTimeClient(transport: { request in
			await gate.block()
			let now = ISO8601DateFormatter().string(from: Date())
			let raw = #"{"schema_version":1,"source":"tyfloswiat.pl","type":"posts","items":[{"id":1,"freshness":"fresh","checked_at":"\#(now)","tyflocentrum":{"schema_version":1,"text_status":"ready","word_count":200,"reading_minutes":1}}]}"#
			return (Data(raw.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let summary = WPPostSummary(id: 1, date: "", title: .init(rendered: "Test"), link: "https://tyfloswiat.pl/?p=1")
		let requests = [ContentTimeRequest(summary, kind: .posts)]
		let state = ContentTimeListState()
		let old = Task { await state.load(requests, refreshing: false, client: client) }
		while !(await gate.started) {
			await Task.yield()
		}
		await state.load([], refreshing: true, client: client)
		await gate.release()
		await old.value
		XCTAssertTrue(state.records.isEmpty)
		XCTAssertEqual(state.values(requests, now: Date())[requests[0].key], .unavailable)
	}
}

@MainActor
final class ContentTimeRefreshTests: XCTestCase {
	private final class Clock: @unchecked Sendable {
		private let lock = NSLock()
		private var date = Date()
		func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
		func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date += seconds }
	}

	private actor Server {
		var stage = 0
		var calls = 0
		var holdNext = false
		var held: CheckedContinuation<Void, Never>?
		func set(_ stage: Int) { self.stage = stage }
		func hold() { holdNext = true }
		func release() { held?.resume(); held = nil }
		func receive(_ request: URLRequest) async throws -> (Data, URLResponse) {
			calls += 1
			let captured = stage
			if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
			let url = request.url!
			if captured == 5 {
				return (Data(), HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "90"])!)
			}
			let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
			let ids = q.first { $0.name == "ids" }!.value!.split(separator: ",").compactMap { Int($0) }
			let status = captured > 0 && captured < 3 ? "ready" : "missing"
			let items: [[String: Any]] = ids.map {
				["id": $0, "freshness": "fresh", "checked_at": ISO8601DateFormatter().string(from: Date()),
				 "tyflocentrum": ["schema_version": 1, "word_count": captured == 2 ? 1201 : 1001,
				                  "reading_minutes": captured == 2 ? 7 : 6, "text_status": status]]
			}
			let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1, "source": "tyfloswiat.pl", "type": "posts", "items": items])
			return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		}
	}

	private func requests(_ count: Int = 1) -> [ContentTimeRequest] {
		(1 ... count).map { ContentTimeRequest(WPPostSummary(id: $0, date: "", title: .init(rendered: "Stały tytuł"), link: "https://tyfloswiat.pl/?p=\($0)"), kind: .posts) }
	}

	private func waitUntilHeld(_ server: Server) async throws {
		for _ in 0 ..< 1000 {
			if await server.held != nil { return }
			try await Task.sleep(nanoseconds: 1_000_000)
		}
		XCTFail("Transport nie dotarł do bramki")
	}

	func testRevisionAndResumeRespectAgeButManualBypassesNegativeCache() async throws {
		let clock = Clock()
		let server = Server()
		let client = ContentTimeClient(clock: { clock.now() }, transport: { try await server.receive($0) })
		let state = ContentTimeListState()
		let input = requests()
		await state.update(input, revision: 0, activation: 0, client: client, now: clock.now())
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .unavailable)
		await server.set(1)
		await state.update(input, revision: 0, activation: 1, client: client, now: clock.now())
		let before = await server.calls
		XCTAssertEqual(before, 1)
		await state.update(input, revision: 1, activation: 1, client: client, now: clock.now())
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(6))
		await server.set(2)
		clock.advance(119)
		await state.update(input, revision: 1, activation: 2, client: client, now: clock.now())
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(6))
		clock.advance(1)
		await state.update(input, revision: 1, activation: 3, client: client, now: clock.now())
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(7))
		let after = await server.calls
		XCTAssertEqual(after, 3)
	}

	func testRefreshWhileLoadingOldReplyCannotUndoNewGeneration() async throws {
		let server = Server()
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let state = ContentTimeListState()
		let input = requests()
		await server.set(1)
		await state.update(input, revision: 0, activation: 0, client: client)
		await server.hold()
		let old = Task { await state.update(input, revision: 1, activation: 0, client: client) }
		try await waitUntilHeld(server)
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(6), "Nie migocze podczas odświeżania")
		await server.set(2)
		await state.update(input, revision: 2, activation: 0, client: client)
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(7))
		await server.release()
		await old.value
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(7))
		let cached = await client.fetch(input.map(\.key))
		XCTAssertEqual(cached[input[0].key]?.readingTime(now: Date(), sourceModified: nil), .reading(7))
	}

	func testCancellationAndReturnKeepLatestGeneration() async throws {
		let server = Server()
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let state = ContentTimeListState()
		let input = requests()
		await server.set(1)
		await server.hold()
		let old = Task { await state.update(input, revision: 1, activation: 0, client: client) }
		try await waitUntilHeld(server)
		old.cancel()
		await server.set(2)
		await state.update(input, revision: 2, activation: 0, client: client)
		await server.release()
		await old.value
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(7))
		let active = await client.activeCount
		XCTAssertEqual(active, 0)
	}

	func testManualRefreshHonorsRetryAfterAndFailureDoesNotLoop() async throws {
		let server = Server()
		let clock = Clock()
		let client = ContentTimeClient(clock: { clock.now() }, transport: { try await server.receive($0) })
		let state = ContentTimeListState()
		let input = requests()
		await server.set(5)
		await state.update(input, revision: 0, activation: 0, client: client, now: clock.now())
		for revision in 1 ... 10 {
			await state.update(input, revision: revision, activation: 0, client: client, now: clock.now())
		}
		let blocked = await server.calls
		XCTAssertEqual(blocked, 1)
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .unavailable)
		clock.advance(90)
		await server.set(1)
		await state.update(input, revision: 11, activation: 0, client: client, now: clock.now())
		XCTAssertEqual(state.values(input, now: Date())[input[0].key], .reading(6))
		let resumed = await server.calls
		XCTAssertEqual(resumed, 2)
	}

	func testForcedRefreshLongerThanCacheIncludesBothEnds() async throws {
		let server = Server()
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let state = ContentTimeListState()
		let input = requests(600)
		await state.update(input, revision: 0, activation: 0, client: client)
		await server.set(1)
		await state.update(input, revision: 1, activation: 0, client: client)
		let values = state.values(input, now: Date())
		XCTAssertTrue(input.allSatisfy { values[$0.key] == .reading(6) })
		let cached = await client.cachedCount
		XCTAssertLessThanOrEqual(cached, 512)
		let count = await server.calls
		XCTAssertEqual(count, 24)
	}
}

@MainActor
final class NewsRefreshOperationTests: XCTestCase {
	func testRedrawCancellationDoesNotCancelOwnedWork() async {
		let owner = NewsRefreshOperation()
		let entered = expectation(description: "Właściciel uruchomił pracę")
		var gate: CheckedContinuation<Void, Never>?
		var completed = false
		var cancelled = true
		let waiter = Task {
			await owner.run {
				entered.fulfill()
				await withCheckedContinuation { gate = $0 }
				cancelled = Task.isCancelled
				completed = true
			}
		}
		await fulfillment(of: [entered], timeout: 2)
		waiter.cancel()
		gate?.resume()
		await waiter.value
		XCTAssertTrue(completed)
		XCTAssertFalse(cancelled)
	}

	func testScreenExitCancelsWorkAndOldCompletionDoesNotClearNewOwner() async {
		let owner = NewsRefreshOperation()
		let firstEntered = expectation(description: "Pierwsza praca")
		let secondEntered = expectation(description: "Praca po powrocie")
		var firstGate: CheckedContinuation<Void, Never>?
		var secondGate: CheckedContinuation<Void, Never>?
		var firstCancelled = false
		var secondCancelled = false
		let first = Task {
			await owner.run {
				firstEntered.fulfill()
				await withCheckedContinuation { firstGate = $0 }
				firstCancelled = Task.isCancelled
			}
		}
		await fulfillment(of: [firstEntered], timeout: 2)
		owner.cancel()
		let second = Task {
			await owner.run {
				secondEntered.fulfill()
				await withCheckedContinuation { secondGate = $0 }
				secondCancelled = Task.isCancelled
			}
		}
		await fulfillment(of: [secondEntered], timeout: 2)
		firstGate?.resume()
		await first.value
		owner.cancel()
		secondGate?.resume()
		await second.value
		XCTAssertTrue(firstCancelled)
		XCTAssertTrue(secondCancelled, "Stary koniec nie może usunąć nowego uchwytu")
		var recovered = false
		await owner.run { recovered = !Task.isCancelled }
		XCTAssertTrue(recovered)
	}

	func testConcurrentGesturesCoalesceWithoutExtraWork() async {
		let owner = NewsRefreshOperation()
		let entered = expectation(description: "Pierwsze pobranie")
		let joined = expectation(description: "Drugie wejście")
		var gate: CheckedContinuation<Void, Never>?
		var calls = 0
		let first = Task {
			await owner.run {
				calls += 1
				entered.fulfill()
				await withCheckedContinuation { gate = $0 }
			}
		}
		await fulfillment(of: [entered], timeout: 2)
		let second = Task {
			joined.fulfill()
			await owner.run { calls += 1 }
		}
		await fulfillment(of: [joined], timeout: 2)
		gate?.resume()
		await first.value
		await second.value
		XCTAssertEqual(calls, 1)
	}

	func testAlreadyCancelledGestureDoesNotStartWork() async {
		let owner = NewsRefreshOperation()
		let entered = expectation(description: "Oczekujący gest")
		var gate: CheckedContinuation<Void, Never>?
		var calls = 0
		let waiter = Task {
			entered.fulfill()
			await withCheckedContinuation { gate = $0 }
			await owner.run { calls += 1 }
		}
		await fulfillment(of: [entered], timeout: 2)
		waiter.cancel()
		gate?.resume()
		await waiter.value
		XCTAssertEqual(calls, 0)
	}
}
