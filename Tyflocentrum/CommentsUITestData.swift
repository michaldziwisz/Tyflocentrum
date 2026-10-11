#if DEBUG
	import Foundation

	/// Osobne, opt-in odpowiedzi aparatury. Nie zmieniają starych fixture.
	enum CommentsUITestData {
		private static let lock = NSLock()
		private static var didStall = false
		private static var didFail = false

		static var enabled: Bool {
			ProcessInfo.processInfo.arguments.contains("UI_TESTING") &&
				ProcessInfo.processInfo.arguments.contains("UI_TESTING_COMMENTS")
		}

		static func matches(_ request: URLRequest) -> Bool {
			enabled && request.url?.path.contains("/wp-json/wp/v2/comments") == true
		}

		private static func isList(_ request: URLRequest) -> Bool {
			guard let url = request.url, matches(request) else { return false }
			return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "per_page" && $0.value == "100" } == true
		}

		static func shouldStall(_ request: URLRequest) -> Bool {
			guard isList(request), ProcessInfo.processInfo.arguments.contains("UI_TESTING_COMMENTS_STALL") else { return false }
			lock.lock(); defer { lock.unlock() }
			guard !didStall else { return false }
			didStall = true
			return true
		}

		static func response(for request: URLRequest) -> (Int, Data)? {
			guard matches(request) else { return nil }
			if ProcessInfo.processInfo.arguments.contains("UI_TESTING_COMMENTS_EMPTY") {
				return (200, Data("[]".utf8))
			}
			if isList(request), ProcessInfo.processInfo.arguments.contains("UI_TESTING_COMMENTS_ERROR") {
				lock.lock()
				let fail = !didFail
				didFail = true
				lock.unlock()
				if fail { return (500, Data("[]".utf8)) }
			}
			let longBody = (1 ... 18).map { "<p>Akapit \($0): Długi komentarz zachowuje akapity, polskie znaki i pełną treść bez rozwijania.</p>" }.joined() + "<p>Koniec długiego komentarza.</p>"
			let items: [[String: Any]] = [
				["id": 1001, "post": 1, "parent": 0, "author_name": "Anna & Piotr", "date": "2026-10-11T10:15:00",
				 "content": ["rendered": "<p>Pierwszy akapit komentarza.</p><p>Drugi akapit komentarza.</p><p><a href=\"https://example.com\">Źródło</a></p><a href=\"javascript:document.body.innerHTML='ATAK'\">Niedozwolony odnośnik</a><script>document.body.innerHTML='ATAK';</script>"]],
				["id": 1002, "post": 1, "parent": 1001, "author_name": "Ewa", "date": "2026-10-11T11:15:00",
				 "content": ["rendered": longBody]],
				["id": 1003, "post": 1, "parent": 999, "author_name": "Ostatni autor", "content": ["rendered": "<p>Ostatni komentarz dyskusji.</p>"]],
			]
			return (200, (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8))
		}
	}
#endif
