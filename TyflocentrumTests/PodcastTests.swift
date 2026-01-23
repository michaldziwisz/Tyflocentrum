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

final class PlaybackRatePolicyTests: XCTestCase {
	func testNextPlaybackRateCyclesForward() {
		XCTAssertEqual(PlaybackRatePolicy.next(after: 1.0), 1.25)
		XCTAssertEqual(PlaybackRatePolicy.next(after: 1.25), 1.5)
		XCTAssertEqual(PlaybackRatePolicy.next(after: 1.5), 1.75)
		XCTAssertEqual(PlaybackRatePolicy.next(after: 1.75), 2.0)
	}

	func testNextPlaybackRateWrapsToBeginning() {
		XCTAssertEqual(PlaybackRatePolicy.next(after: 2.0), 1.0)
	}

	func testNextPlaybackRateTreatsUnknownAsFirst() {
		XCTAssertEqual(PlaybackRatePolicy.next(after: 1.33), 1.25)
	}
}
