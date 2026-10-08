#if DEBUG
	import Foundation

	/// Wyłącznie syntetyczne dane scenariuszy XCTest, nigdy transport produkcyjny.
	enum ContentTimeUITestData {
		static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_CONTENT_TIMES") }
		static var failed: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_METADATA_FAILURE") }

		static func response(_ request: URLRequest) -> (Int, Data)? {
			guard enabled, let url = request.url,
			      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
			let isReading = url.host == "tyflocentrum.tyflo.eu.org"
			let include = query.first { $0.name == "include" }?.value
			guard isReading || (url.host == "tyflopodcast.net" && include != nil) else { return nil }
			if failed { return (503, Data("{}".utf8)) }
			let ids = (include ?? query.first { $0.name == "ids" }?.value ?? "").split(separator: ",").compactMap { Int($0) }
			let items: [[String: Any]] = ids.map { id in
				["id": id, "freshness": "fresh", "checked_at": ISO8601DateFormatter().string(from: Date()),
				 "modified_gmt": "2026-01-20T00:59:40", "tyflocentrum": metadata]
			}
			let object: Any = isReading
				? ["schema_version": 1, "source": "tyfloswiat.pl", "type": query.first { $0.name == "type" }?.value ?? "posts", "items": items]
				: items
			return (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
		}

		static var metadata: [String: Any] {
			["schema_version": 1, "word_count": 1001, "reading_minutes": 6, "text_status": "ready", "audio_status": "ready", "duration_seconds": 4983.1]
		}

		static func decorate(_ data: Data, request: URLRequest) -> Data {
			guard enabled, request.url?.host == "tyflopodcast.net", request.url?.path.contains("/wp/v2/posts") == true,
			      let value = try? JSONSerialization.jsonObject(with: data) else { return data }
			func decorateItem(_ item: [String: Any]) -> [String: Any] {
				var item = item
				item["tyflocentrum"] = failed ? ["duration_seconds": true] : metadata
				return item
			}
			let result: Any
			if let items = value as? [[String: Any]] { result = items.map(decorateItem) }
			else if let item = value as? [String: Any] { result = decorateItem(item) }
			else { return data }
			return (try? JSONSerialization.data(withJSONObject: result)) ?? data
		}
	}
#endif
