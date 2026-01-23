import CoreData
import XCTest

@testable import Tyflocentrum

final class PodcastTests: XCTestCase {
	func testFormattedDateReturnsOriginalForInvalidDate() {
		let podcast = makePodcast(date: "invalid-date")
		XCTAssertEqual(podcast.formattedDate, "invalid-date")
	}

	func testFormattedDateFormatsValidDate() {
		let podcast = makePodcast(date: "2026-01-20T00:59:40")
		XCTAssertNotEqual(podcast.formattedDate, podcast.date)
		XCTAssertFalse(podcast.formattedDate.contains("T"))
		XCTAssertFalse(podcast.formattedDate.contains(":"))
	}

	func testPlainTextStripsHTML() {
		let title = Podcast.PodcastTitle(rendered: "<b>Ala</b> ma kota")
		XCTAssertEqual(title.plainText, "Ala ma kota")
	}

	func testPlainTextReturnsRenderedWhenAlreadyPlain() {
		let title = Podcast.PodcastTitle(rendered: "Ala ma kota")
		XCTAssertEqual(title.plainText, "Ala ma kota")
	}

	private func makePodcast(date: String) -> Podcast {
		let title = Podcast.PodcastTitle(rendered: "Test")
		return Podcast(id: 1, date: date, title: title, excerpt: title, content: title, guid: title)
	}
}

final class DataControllerTests: XCTestCase {
	func testInMemoryStoreDescriptionUsesInMemoryType() {
		let controller = DataController(inMemory: true)
		XCTAssertEqual(controller.container.persistentStoreDescriptions.first?.type, NSInMemoryStoreType)
	}
}
