import Foundation
import XCTest
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif
#if canImport(Tyflocentrum)
	@testable import Tyflocentrum
#endif

final class ContentTimeClientTests: XCTestCase {
	private actor Server {
		var requests: [URLRequest] = []
		var status = 200
		var failure = false
		var duplicate = false
		var hold = false
		var checkedOffset: TimeInterval = 0
		var continuations: [CheckedContinuation<Void, Never>] = []
		func configure(status: Int = 200, failure: Bool = false, duplicate: Bool = false, hold: Bool = false, checkedOffset: TimeInterval = 0) {
			self.status = status; self.failure = failure; self.duplicate = duplicate; self.hold = hold; self.checkedOffset = checkedOffset
		}

		func release() { hold = false; let pending = continuations; continuations = []; pending.forEach { $0.resume() } }
		func receive(_ request: URLRequest) async throws -> (Data, URLResponse) {
			requests.append(request)
			if hold { await withCheckedContinuation { continuations.append($0) } }
			if failure { throw URLError(.timedOut) }
			let url = request.url!
			let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
			let ids = (query["ids"] ?? query["include"]!).split(separator: ",").compactMap { Int($0) }
			let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(checkedOffset))
			var items: [[String: Any]] = ids.reversed().map { id in
				["id": id, "freshness": "fresh", "checked_at": now, "modified_gmt": "2026-10-07T10:00:00", "tyflocentrum": ["schema_version": 1, "text_status": "ready", "word_count": id * 200, "reading_minutes": id, "audio_status": "ready", "duration_seconds": 60.1]]
			}
			items.append(["id": 999_999, "tyflocentrum": ["schema_version": 1]])
			items.append(["id": "bad", "tyflocentrum": false])
			if duplicate, let first = items.first { items.append(first) }
			let body: Any = query["include"] != nil ? items : ["schema_version": 1, "source": "tyfloswiat.pl", "type": query["type"]!, "items": items]
			return try (JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
		}

		var count: Int { requests.count }
	}

	private final class ClockBox: @unchecked Sendable {
		private let lock = NSLock()
		private var date = Date()
		func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
		func advance(_ interval: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(interval) }
	}

	func testExpiredRecordUsesNegativeCacheInsteadOfRetryStorm() async {
		let server = Server()
		await server.configure(checkedOffset: -86401)
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let key = ContentTimeKey(kind: .posts, id: 1)
		for _ in 0 ..< 3 {
			let result = await client.fetch([key])
			XCTAssertEqual(result[key]?.readingTime(now: Date(), sourceModified: nil), .unavailable)
		}
		let count = await server.count
		XCTAssertEqual(count, 1)
	}

	func testCacheAndUnknownTTLExpireWithoutRestart() async {
		let clock = ClockBox()
		let server = Server()
		await server.configure(status: 503)
		let client = ContentTimeClient(clock: { clock.now() }, transport: { try await server.receive($0) })
		let key = ContentTimeKey(kind: .posts, id: 1)
		_ = await client.fetch([key])
		clock.advance(31)
		await server.configure()
		let result = await client.fetch([key])
		XCTAssertEqual(result.count, 1)
		XCTAssertEqual(result[key]?.readingTime(now: clock.now().addingTimeInterval(86401), sourceModified: nil), .unavailable)
		clock.advance(301)
		_ = await client.fetch([key])
		let count = await server.count
		XCTAssertEqual(count, 3)
	}

	func testMalformedEnvelopeAndMissingItemAreUnknown() async {
		let bodies = ["null", "[]", "not json", #"{"schema_version":true,"source":"tyfloswiat.pl","type":"posts","items":[]}"#,
		              #"{"schema_version":2,"source":"tyfloswiat.pl","type":"posts","items":[]}"#,
		              #"{"schema_version":1,"source":"other","type":"posts","items":[]}"#,
		              #"{"schema_version":1,"source":"tyfloswiat.pl","type":"pages","items":[]}"#,
		              #"{"schema_version":1,"source":"tyfloswiat.pl","type":"posts","items":[null,false,{}, {"id":"1"}]}"#]
		for body in bodies {
			let client = ContentTimeClient(transport: { request in
				(Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
			})
			let result = await client.fetch([ContentTimeKey(kind: .posts, id: 1)])
			XCTAssertTrue(result.isEmpty, body)
		}
	}

	func testIndependentDeadlineCancelsTransport() async {
		let started = Date()
		let client = ContentTimeClient(timeout: 0.05, transport: { request in
			try await Task.sleep(nanoseconds: 10_000_000_000)
			return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
		})
		let result = await client.fetch([ContentTimeKey(kind: .posts, id: 1)])
		XCTAssertTrue(result.isEmpty)
		XCTAssertLessThan(Date().timeIntervalSince(started), 1)
		let active = await client.activeCount
		XCTAssertEqual(active, 0)
	}

	private func waitForRequests(_ count: Int, server: Server) async {
		for _ in 0 ..< 1000 {
			if await server.count >= count { return }
			try? await Task.sleep(nanoseconds: 1_000_000)
		}
		XCTFail("Żądanie nie dotarło do transportu")
	}

	func testBatchLimitDedupReversedOrderTypesAndNoMediaRequests() async {
		let server = Server()
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let keys = (1 ... 101).map { ContentTimeKey(kind: .posts, id: $0) }
			+ [ContentTimeKey(kind: .pages, id: 1), ContentTimeKey(kind: .posts, id: 1), ContentTimeKey(kind: .posts, id: 0), ContentTimeKey(kind: .posts, id: 2_147_483_648)]
		let records = await client.fetch(keys)
		XCTAssertEqual(records.count, 102)
		XCTAssertEqual(records[ContentTimeKey(kind: .posts, id: 2)]?.tyflocentrum?.validReadingMinutes, 2)
		XCTAssertNotNil(records[ContentTimeKey(kind: .pages, id: 1)])
		let requests = await server.requests
		XCTAssertEqual(requests.count, 4)
		for request in requests {
			XCTAssertEqual(request.url?.host, "tyflocentrum.tyflo.eu.org")
			XCTAssertEqual(request.url?.path, "/v1/metadata")
			XCTAssertEqual(request.timeoutInterval, 3)
			let ids = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "ids" }!.value!.split(separator: ",")
			XCTAssertLessThanOrEqual(ids.count, 50)
			XCTAssertEqual(Set(ids).count, ids.count)
		}
		_ = await client.fetch(keys)
		let cachedRequests = await server.count
		XCTAssertEqual(cachedRequests, 4)
	}

	func testUnknownResultsAndErrorsDoNotRetryStorm() async {
		for status in [429, 503, 200] {
			let server = Server()
			await server.configure(status: status, failure: status == 200)
			let client = ContentTimeClient(transport: { try await server.receive($0) })
			for _ in 0 ..< 10 {
				let result = await client.fetch([ContentTimeKey(kind: .posts, id: 1)])
				XCTAssertTrue(result.isEmpty)
			}
			let count = await server.count
			XCTAssertEqual(count, 1)
		}
	}

	func testOverlappingActiveBatchesShareTransport() async {
		let server = Server()
		await server.configure(hold: true)
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let key = ContentTimeKey(kind: .posts, id: 1)
		let first = Task { await client.fetch([key]) }
		await waitForRequests(1, server: server)
		let second = Task { await client.fetch([key]) }
		try? await Task.sleep(nanoseconds: 20_000_000)
		await server.release()
		let a = await first.value; let b = await second.value
		XCTAssertEqual(a.count, 1); XCTAssertEqual(b.count, 1)
		let count = await server.count
		XCTAssertEqual(count, 1)
	}

	func testCancelledLateCallbackCannotFillCacheOrReplaceRefresh() async {
		let server = Server()
		await server.configure(hold: true)
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let key = ContentTimeKey(kind: .posts, id: 1)
		let old = Task { await client.fetch([key]) }
		await waitForRequests(1, server: server)
		old.cancel()
		await client.invalidate([key])
		await server.release()
		let discarded = await old.value
		XCTAssertTrue(discarded.isEmpty)
		let cached = await client.cachedCount
		XCTAssertEqual(cached, 0)
		let fresh = await client.fetch([key])
		XCTAssertEqual(fresh.count, 1)
		let count = await server.count
		XCTAssertEqual(count, 2)
	}

	func testDuplicatesAreUnknownAndCacheIsBounded() async {
		let server = Server()
		await server.configure(duplicate: true)
		let client = ContentTimeClient(capacity: 3, transport: { try await server.receive($0) })
		let result = await client.fetch((1 ... 10).map { ContentTimeKey(kind: .posts, id: $0) })
		XCTAssertNil(result[ContentTimeKey(kind: .posts, id: 10)])
		XCTAssertEqual(result.count, 9)
		let count = await client.cachedCount
		XCTAssertEqual(count, 3)
	}

	func testAudioFavoritesOnlyRequestOptionalMetadata() async {
		let server = Server()
		let client = ContentTimeClient(transport: { try await server.receive($0) })
		let key = ContentTimeKey(kind: .podcast, id: 1)
		let result = await client.fetch([key])
		XCTAssertEqual(result[key]?.tyflocentrum?.audioSeconds, 61)
		let requests = await server.requests
		let url = requests[0].url!
		XCTAssertEqual(url.path, "/wp-json/wp/v2/posts")
		let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "_fields" }!.value
		XCTAssertEqual(fields, "id,tyflocentrum")
	}
}
