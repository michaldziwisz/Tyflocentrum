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
