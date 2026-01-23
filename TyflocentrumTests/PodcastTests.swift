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

final class ResumePositionStoreTests: XCTestCase {
	func testMakeKeyUsesAbsoluteString() {
		let url = URL(string: "https://example.com/audio.mp3?x=1")!
		XCTAssertEqual(ResumePositionStore.makeKey(for: url), "resume.\(url.absoluteString)")
	}

	func testLoadReturnsNilWhenMissing() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let store = ResumePositionStore(userDefaults: defaults)
		XCTAssertNil(store.load(forKey: "missing"))
	}

	func testLoadReturnsNilWhenValueIsTooSmall() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var store = ResumePositionStore(userDefaults: defaults)
		store.save(1, forKey: key)

		XCTAssertNil(store.load(forKey: key))
	}

	func testLoadReturnsValueWhenGreaterThanOne() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var store = ResumePositionStore(userDefaults: defaults)
		store.save(12.5, forKey: key)

		XCTAssertEqual(store.load(forKey: key), 12.5)
	}

	func testClearRemovesValue() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var store = ResumePositionStore(userDefaults: defaults)
		store.save(12.5, forKey: key)
		store.clear(forKey: key)

		XCTAssertNil(store.load(forKey: key))
	}

	func testMaybeSaveThrottlesWrites() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var now = Date(timeIntervalSince1970: 0)
		var store = ResumePositionStore(userDefaults: defaults, now: { now }, throttleInterval: 5)

		store.maybeSave(10, forKey: key)
		XCTAssertEqual(store.load(forKey: key), 10)

		now = now.addingTimeInterval(4)
		store.maybeSave(11, forKey: key)
		XCTAssertEqual(store.load(forKey: key), 10)

		now = now.addingTimeInterval(1)
		store.maybeSave(11, forKey: key)
		XCTAssertEqual(store.load(forKey: key), 11)
	}

	func testSaveIgnoresNonFinite() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var store = ResumePositionStore(userDefaults: defaults)
		store.save(.nan, forKey: key)
		XCTAssertNil(store.load(forKey: key))
	}

	func testMaybeSaveIgnoresNonFinite() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let key = "resume.test"
		var store = ResumePositionStore(userDefaults: defaults)
		store.save(10, forKey: key)
		store.maybeSave(.nan, forKey: key)

		XCTAssertEqual(store.load(forKey: key), 10)
	}
}
