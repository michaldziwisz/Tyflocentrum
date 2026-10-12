import Foundation
import XCTest

@testable import Tyflocentrum

final class CommentPresentationTests: XCTestCase {
	private func comment(_ id: Int = 1, parent: Int = 0, author: String = "Jan", body: String = "<p>Treść</p>", date: String? = nil) -> Comment {
		Comment(id: id, post: 123, parent: parent, authorName: author, content: .init(rendered: body), date: date)
	}

	func testOldPayloadWithoutDateStillDecodes() throws {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		let value = try decoder.decode(Comment.self, from: Data(#"{"id":1,"post":123,"parent":0,"author_name":"Jan","content":{"rendered":"<p>Treść</p>"}}"#.utf8))
		XCTAssertNil(value.date)
		XCTAssertNil(value.formattedDate)
		XCTAssertEqual(value.content.rendered, "<p>Treść</p>")
	}

	func testDateIsDecodedAndKeepsWordPressWallClock() throws {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		let value = try decoder.decode(Comment.self, from: Data(#"{"id":1,"post":123,"parent":0,"author_name":"Jan","date":"2026-10-11T23:07:00","content":{"rendered":"OK"}}"#.utf8))
		XCTAssertEqual(value.formattedDate, "11 października 2026, 23:07")
		XCTAssertTrue(CommentHTMLDocument.body(comments: [value]).contains("11 października 2026, 23:07"))
	}

	func testMissingAndInvalidDatesDoNotInventPublicationTime() {
		for raw in [nil, "", "nie data", "2026-02-31T10:00:00", "2026-10-11T23:07:00<tr>"] as [String?] {
			XCTAssertNil(comment(date: raw).formattedDate)
		}
	}

	func testCompleteLongHTMLAndLinksArePreserved() {
		let original = "<p>Zażółć gęślą jaźń.</p>" + String(repeating: "<p>Długi akapit.</p>", count: 200) + "<p>KONIEC <a href=\"https://example.com/?a=1&amp;b=2\">Źródło</a></p>"
		let html = CommentHTMLDocument.body(comments: [comment(body: original)])
		XCTAssertTrue(html.contains(original))
		XCTAssertFalse(html.contains("line-clamp"))
		XCTAssertFalse(html.contains("max-height"))
		XCTAssertFalse(html.contains("Rozwiń"))
	}

	func testReplyNamesLoadedParentRegardlessOfOrder() {
		let html = CommentHTMLDocument.body(comments: [comment(2, parent: 1), comment(1, author: "Anna & Piotr")])
		XCTAssertTrue(html.contains("Odpowiedź na komentarz nr 1: Anna &amp; Piotr"))
		XCTAssertLessThan(html.range(of: "id=\"comment-2\"")!.lowerBound, html.range(of: "id=\"comment-1\"")!.lowerBound)
	}

	func testReplyOutsideLoadedPortionHasExplicitFallback() {
		let html = CommentHTMLDocument.body(comments: [comment(parent: 999)])
		XCTAssertTrue(html.contains("Odpowiedź na komentarz nr 999"))
		XCTAssertFalse(html.contains("Odpowiedź na komentarz nr 999: Jan"))
	}

	func testAuthorCannotInjectMarkupIntoMetadata() {
		let html = CommentHTMLDocument.body(comments: [comment(author: "<script>\"'&</script>")])
		XCTAssertTrue(html.contains("&lt;script&gt;&quot;&#39;&amp;&lt;/script&gt;"))
		XCTAssertFalse(html.contains("<script>"))
	}

	func testCommentsRemainSeparateListItemsAndHeadings() {
		let html = CommentHTMLDocument.body(comments: [comment(1), comment(2)])
		XCTAssertTrue(html.contains("role=\"list\""))
		XCTAssertEqual(html.components(separatedBy: "<li ").count - 1, 2)
		XCTAssertEqual(html.components(separatedBy: "<h2 ").count - 1, 2)
		XCTAssertTrue(html.contains("id=\"comment-author-1\""))
		XCTAssertTrue(html.contains("id=\"comment-author-2\""))
		XCTAssertFalse(html.contains("aria-hidden"))
	}
}
