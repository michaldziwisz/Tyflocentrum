import Foundation

/// Semantyczna lista, nie jedna etykieta dostępności. Nagłówki, akapity i linki
/// pozostają osobnymi elementami WebKita; cała lista ma tylko jeden scroll.
/// Treść przechodzi przez istniejący SafeHTMLView z CSP i wyłączonym JavaScript.
enum CommentHTMLDocument {
	static func body(comments: [Comment]) -> String {
		let authors = Dictionary(comments.map { ($0.id, $0.authorName) }, uniquingKeysWith: { first, _ in first })
		let rows = comments.map { comment in
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
