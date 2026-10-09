import Foundation
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif

/// Osobny, ograniczony cache. Nie pobiera HTML ani nagrań, nie ponawia błędów.
actor ContentTimeClient {
	typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
	private struct Entry {
		let record: ContentTimeRecord?
		let expires: Date
	}

	private struct Response {
		var records: [ContentTimeKey: ContentTimeRecord] = [:]
		var retryAfter: String?
	}

	private struct Flight {
		let keys: [ContentTimeKey]
		let task: Task<Response, Never>
		var waiters: Set<UUID>
		var stored = false
	}

	private let transport: Transport
	private let clock: @Sendable () -> Date
	private let capacity: Int
	private let timeout: TimeInterval
	private var retryUntil: [String: Date] = [:]
	private var cache: [ContentTimeKey: Entry] = [:]
	private var flights: [UUID: Flight] = [:]
	private var keyFlights: [ContentTimeKey: UUID] = [:]

	init(session: URLSession = .shared, capacity: Int = 512, timeout: TimeInterval = 3,
	     clock: @escaping @Sendable () -> Date = { Date() }, transport: Transport? = nil)
	{
		self.transport = transport ?? { try await session.data(for: $0) }
		self.clock = clock
		self.capacity = max(1, capacity)
		self.timeout = timeout
	}

	func invalidate(_ keys: [ContentTimeKey]) {
		let ids = Set(keys.compactMap { keyFlights[$0] })
		for id in ids {
			removeFlight(id)
		}
		for key in keys {
			cache[key] = nil
		}
	}

	func fetch(_ requested: [ContentTimeKey]) async -> [ContentTimeKey: ContentTimeRecord] {
		guard !Task.isCancelled else { return [:] }
		let keys = Array(Set(requested.filter(\.isValid))).sorted {
			$0.kind.rawValue == $1.kind.rawValue ? $0.id < $1.id : $0.kind.rawValue < $1.kind.rawValue
		}
		let now = clock()
		cache = cache.filter { $0.value.expires > now }
		var output: [ContentTimeKey: ContentTimeRecord] = [:]
		var needed: [ContentTimeKey] = []
		let waiter = UUID()
		var flightIDs = Set<UUID>()
		for key in keys {
			if let entry = cache[key] {
				output[key] = entry.record
			} else if let id = keyFlights[key] {
				flights[id]?.waiters.insert(waiter)
				flightIDs.insert(id)
			} else if (retryUntil[key.source] ?? .distantPast) <= now {
				needed.append(key)
			}
		}
		for kind in ContentTimeKey.Kind.allCases {
			let group = needed.filter { $0.kind == kind }
			for start in stride(from: 0, to: group.count, by: 50) {
				let chunk = Array(group[start ..< min(start + 50, group.count)])
				let id = UUID()
				let transport = self.transport
				let timeout = self.timeout
				let task = Task { await Self.request(chunk, timeout: timeout, transport: transport) }
				flights[id] = Flight(keys: chunk, task: task, waiters: [waiter])
				for key in chunk {
					keyFlights[key] = id
				}
				flightIDs.insert(id)
			}
		}
		let ids = flightIDs
		return await withTaskCancellationHandler {
			defer { release(waiter, from: ids) }
			for id in ids {
				guard let flight = flights[id] else { continue }
				let response = await flight.task.value
				let records = response.records
				guard !Task.isCancelled else { return [:] }
				// Odpowiedź po anulowaniu/odświeżeniu nie odtwarza skasowanego cache.
				guard var active = flights[id], active.waiters.contains(waiter) else { continue }
				if !active.stored {
					let received = clock()
					if let header = response.retryAfter, let source = active.keys.first?.source {
						let deadline: Date
						if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
							deadline = received.addingTimeInterval(seconds)
						} else {
							let parser = DateFormatter()
							parser.locale = Locale(identifier: "en_US_POSIX")
							parser.timeZone = TimeZone(secondsFromGMT: 0)
							parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
							deadline = parser.date(from: header) ?? received.addingTimeInterval(30)
						}
						retryUntil[source] = max(retryUntil[source] ?? .distantPast, deadline)
					}
					for key in active.keys {
						let record = records[key]
						let valid = key.kind == .podcast
							? record?.tyflocentrum?.audioSeconds != nil
							: record?.readingTime(now: received, sourceModified: nil) != .unavailable && record != nil
						let ttl = valid ? 300.0 : 30.0
						var expires = received.addingTimeInterval(ttl)
						if valid, key.kind != .podcast, let deadline = record?.expiresAt { expires = min(expires, deadline) }
						cache[key] = Entry(record: record, expires: expires)
					}
					active.stored = true
					flights[id] = active
					prune()
				}
				for key in active.keys where keys.contains(key) {
					output[key] = records[key]
				}
			}
			return output
		} onCancel: {
			Task { await self.release(waiter, from: ids) }
		}
	}

	var cachedCount: Int { cache.count }
	var activeCount: Int { flights.count }

	private func prune() {
		while cache.count > capacity, let key = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
			cache[key] = nil
		}
	}

	private func release(_ waiter: UUID, from ids: Set<UUID>) {
		for id in ids {
			flights[id]?.waiters.remove(waiter)
			if flights[id]?.waiters.isEmpty == true { removeFlight(id) }
		}
	}

	private func removeFlight(_ id: UUID) {
		guard let flight = flights.removeValue(forKey: id) else { return }
		flight.task.cancel()
		for key in flight.keys where keyFlights[key] == id {
			keyFlights[key] = nil
		}
	}

	private struct Batch: Decodable {
		let schema_version: Int
		let source: String
		let type: String
		let items: [ContentTimeRecord]
	}

	private static func request(_ keys: [ContentTimeKey], timeout: TimeInterval, transport: @escaping Transport) async -> Response {
		guard let first = keys.first else { return Response() }
		let ids = keys.map { String($0.id) }.joined(separator: ",")
		let base = first.kind == .podcast
			? "https://tyflopodcast.net/wp-json/wp/v2/posts"
			: "https://tyflocentrum.tyflo.eu.org/v1/metadata"
		guard var url = URLComponents(string: base) else { return Response() }
		url.queryItems = first.kind == .podcast ? [
			URLQueryItem(name: "include", value: ids),
			URLQueryItem(name: "per_page", value: "50"),
			URLQueryItem(name: "context", value: "embed"),
			URLQueryItem(name: "_fields", value: "id,tyflocentrum"),
		] : [
			URLQueryItem(name: "source", value: first.source),
			URLQueryItem(name: "type", value: first.kind.rawValue),
			URLQueryItem(name: "ids", value: ids),
		]
		guard let address = url.url else { return Response() }
		var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		do {
			try Task.checkCancellation()
			let prepared = request
			let (data, response) = try await withTimeout(timeout) { try await transport(prepared) }
			try Task.checkCancellation()
			guard let http = response as? HTTPURLResponse else { return Response() }
			if http.statusCode == 429 || http.statusCode == 503 {
				return Response(retryAfter: http.value(forHTTPHeaderField: "Retry-After") ?? "30")
			}
			guard http.statusCode == 200, data.count <= 256 * 1024 else { return Response() }
			let records: [ContentTimeRecord]
			if first.kind == .podcast {
				records = try JSONDecoder().decode([ContentTimeRecord].self, from: data)
			} else {
				let batch = try JSONDecoder().decode(Batch.self, from: data)
				guard batch.schema_version == 1, batch.source == first.source, batch.type == first.kind.rawValue else { return Response() }
				records = batch.items
			}
			let allowed = Set(keys)
			var seen = Set<ContentTimeKey>()
			var duplicated = Set<ContentTimeKey>()
			var result: [ContentTimeKey: ContentTimeRecord] = [:]
			for record in records {
				guard let id = record.id else { continue }
				let key = ContentTimeKey(kind: first.kind, id: id)
				guard allowed.contains(key) else { continue }
				if !seen.insert(key).inserted { duplicated.insert(key) }
				result[key] = record
			}
			for key in duplicated {
				result[key] = nil
			}
			return Response(records: result)
		} catch { return Response() }
	}
}
