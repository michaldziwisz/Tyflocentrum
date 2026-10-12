import Foundation

/// Semantyczna lista, nie jedna etykieta dostępności. Nagłówki, akapity i linki
/// pozostają osobnymi elementami WebKita; cała lista ma tylko jeden scroll.
/// Treść przechodzi przez istniejący SafeHTMLView z CSP i wyłączonym JavaScript.
enum CommentHTMLDocument {
	/// Kolejność wyświetlania zgodna z Windows (PodcastCommentThreadBuilder): wątki od
	/// najstarszego, odpowiedzi tuż pod komentarzem nadrzędnym, również od najstarszej.
	/// Komentarz z datą przed komentarzem bez daty. Przy równych lub brakujących datach
	/// odwracamy kolejność źródła, bo WordPress domyślnie zwraca najnowsze najpierw.
	/// Odpowiedź do komentarza spoza pobranej porcji staje się początkiem wątku.
	static func displayOrder(_ comments: [Comment]) -> [Comment] {
		guard comments.count > 1 else { return comments }
		var sourceIndex: [Int: Int] = [:]
		for (index, comment) in comments.enumerated() where sourceIndex[comment.id] == nil {
			sourceIndex[comment.id] = index
		}
		let timestamps = Dictionary(comments.map { ($0.id, $0.publishedAt) }, uniquingKeysWith: { first, _ in first })

		func precedes(_ left: Comment, _ right: Comment) -> Bool {
			let leftDate = timestamps[left.id] ?? nil
			let rightDate = timestamps[right.id] ?? nil
			if let leftDate, let rightDate, leftDate != rightDate {
				return leftDate < rightDate
			}
			if (leftDate == nil) != (rightDate == nil) {
				return leftDate != nil
			}
			let leftIndex = sourceIndex[left.id] ?? 0
			let rightIndex = sourceIndex[right.id] ?? 0
			if leftIndex != rightIndex {
				return leftIndex > rightIndex
			}
			return left.id < right.id
		}

		let loadedIDs = Set(comments.map(\.id))
		var children: [Int: [Comment]] = [:]
		for comment in comments where comment.parent != 0 && loadedIDs.contains(comment.parent) {
			children[comment.parent, default: []].append(comment)
		}
		let roots = comments.filter { $0.parent == 0 || !loadedIDs.contains($0.parent) }

		var ordered: [Comment] = []
		ordered.reserveCapacity(comments.count)
		var visited = Set<Int>()
		func append(_ comment: Comment) {
			guard visited.insert(comment.id).inserted else { return }
			ordered.append(comment)
			for child in (children[comment.id] ?? []).sorted(by: precedes) {
				append(child)
			}
		}
		for root in roots.sorted(by: precedes) {
			append(root)
		}
		// Cykl rodziców w uszkodzonych danych: nic nie może zniknąć z listy.
		for comment in comments.sorted(by: precedes) where !visited.contains(comment.id) {
			append(comment)
		}
		return ordered
	}

	static func body(comments: [Comment]) -> String {
		let authors = Dictionary(comments.map { ($0.id, $0.authorName) }, uniquingKeysWith: { first, _ in first })
		let rows = displayOrder(comments).map { comment in
			let date = comment.formattedDate.map { "<p class=\"comment-meta\">\(escape($0))</p>" } ?? ""
			var reply = ""
			if comment.parent > 0 {
				let author = authors[comment.parent].map { ": \(escape($0))" } ?? ""
				reply = "<p class=\"comment-meta\">Odpowiedź na komentarz nr \(comment.parent)\(author)</p>"
			}
			return """
			<li id="comment-\(comment.id)">
			  <article aria-labelledby="comment-author-\(comment.id)">
			    <h2 id="comment-author-\(comment.id)">\(escape(comment.authorName))</h2>
			    \(date)\(reply)
			    <div class="comment-body">\(comment.content.rendered)</div>
			  </article>
			</li>
			"""
		}.joined(separator: "\n")
		return """
		<style>
		  .podcast-comments { list-style: none; margin: 0; padding: 0; }
		  .podcast-comments > li { padding: 0 0 1em; margin: 0 0 1em; border-bottom: 1px solid GrayText; }
		  .podcast-comments h2 { font-size: 1.1em; margin: 0 0 .4em; }
		  .comment-meta { margin: .3em 0; }
		  .comment-body { margin-top: .75em; }
		</style>
		<ol class="podcast-comments" role="list">
		\(rows)
		</ol>
		"""
	}

	private static func escape(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&#39;")
	}
}
