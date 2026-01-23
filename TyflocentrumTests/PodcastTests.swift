import CoreData
import MediaPlayer
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

final class SeekPolicyTests: XCTestCase {
	func testClampedTimeReturnsNilForNonFinite() {
		XCTAssertNil(SeekPolicy.clampedTime(.nan))
		XCTAssertNil(SeekPolicy.clampedTime(.infinity))
		XCTAssertNil(SeekPolicy.clampedTime(-.infinity))
	}

	func testClampedTimeClampsNegativeToZero() {
		XCTAssertEqual(SeekPolicy.clampedTime(-10), 0)
		XCTAssertEqual(SeekPolicy.clampedTime(10), 10)
	}

	func testTargetTimeAddsDeltaAndClampsToZero() {
		XCTAssertEqual(SeekPolicy.targetTime(elapsed: 10, delta: 30), 40)
		XCTAssertEqual(SeekPolicy.targetTime(elapsed: 10, delta: -30), 0)
	}

	func testTargetTimeReturnsNilForNonFinite() {
		XCTAssertNil(SeekPolicy.targetTime(elapsed: .nan, delta: 1))
		XCTAssertNil(SeekPolicy.targetTime(elapsed: 1, delta: .nan))
	}
}

@MainActor
final class MediaPlayerIntegrationTests: XCTestCase {
	override func tearDown() {
		let nowPlaying = MPNowPlayingInfoCenter.default()
		nowPlaying.nowPlayingInfo = nil
		nowPlaying.playbackState = .stopped
		super.tearDown()
	}

	func testRemoteSkipCommandsPrefer30Seconds() {
		var audioPlayer: AudioPlayer? = AudioPlayer()
		defer {
			audioPlayer?.stop()
			audioPlayer = nil
		}

		let commandCenter = MPRemoteCommandCenter.shared()
		XCTAssertEqual(commandCenter.skipForwardCommand.preferredIntervals, [30])
		XCTAssertEqual(commandCenter.skipBackwardCommand.preferredIntervals, [30])
	}

	func testRemoteCommandAvailabilityFollowsPlaybackStateAndLiveFlag() throws {
		let commandCenter = MPRemoteCommandCenter.shared()

		var audioPlayer: AudioPlayer? = AudioPlayer()
		defer {
			audioPlayer?.stop()
			audioPlayer = nil
		}

		audioPlayer?.stop()

		XCTAssertFalse(commandCenter.playCommand.isEnabled)
		XCTAssertFalse(commandCenter.pauseCommand.isEnabled)
		XCTAssertFalse(commandCenter.skipForwardCommand.isEnabled)
		XCTAssertFalse(commandCenter.skipBackwardCommand.isEnabled)
		XCTAssertFalse(commandCenter.changePlaybackPositionCommand.isEnabled)
		XCTAssertFalse(commandCenter.changePlaybackRateCommand.isEnabled)

		let nonLiveURL = try makeTempAudioURL()
		audioPlayer?.play(url: nonLiveURL, title: "Title", subtitle: "Subtitle", isLiveStream: false)

		XCTAssertTrue(commandCenter.playCommand.isEnabled)
		XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
		XCTAssertTrue(commandCenter.skipForwardCommand.isEnabled)
		XCTAssertTrue(commandCenter.skipBackwardCommand.isEnabled)
		XCTAssertTrue(commandCenter.changePlaybackPositionCommand.isEnabled)
		XCTAssertTrue(commandCenter.changePlaybackRateCommand.isEnabled)

		let liveURL = try makeTempAudioURL(fileExtension: "m3u8")
		audioPlayer?.play(url: liveURL, title: "Live", subtitle: nil, isLiveStream: true)

		XCTAssertTrue(commandCenter.playCommand.isEnabled)
		XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
		XCTAssertFalse(commandCenter.skipForwardCommand.isEnabled)
		XCTAssertFalse(commandCenter.skipBackwardCommand.isEnabled)
		XCTAssertFalse(commandCenter.changePlaybackPositionCommand.isEnabled)
		XCTAssertFalse(commandCenter.changePlaybackRateCommand.isEnabled)
	}

	func testNowPlayingMetadataIsUpdatedAndClearedOnStop() throws {
		let nowPlaying = MPNowPlayingInfoCenter.default()
		nowPlaying.nowPlayingInfo = nil
		nowPlaying.playbackState = .stopped

		var audioPlayer: AudioPlayer? = AudioPlayer()
		defer {
			audioPlayer?.stop()
			audioPlayer = nil
		}

		let url = try makeTempAudioURL()
		audioPlayer?.play(url: url, title: "Test title", subtitle: "Test subtitle", isLiveStream: false)

		let info = try XCTUnwrap(nowPlaying.nowPlayingInfo)
		XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Test title")
		XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Test subtitle")
		XCTAssertEqual(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false)

		audioPlayer?.stop()

		XCTAssertNil(nowPlaying.nowPlayingInfo)
		XCTAssertEqual(nowPlaying.playbackState, .stopped)
	}

	private func makeTempAudioURL(fileExtension: String = "mp3") throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension(fileExtension)
		try Data().write(to: url)
		return url
	}
}

final class RemoteCommandWiringTests: XCTestCase {
	func testRemoteCommandWiringInvokesExpectedHandlers() {
		let center = FakeRemoteCommandCenter()

		var playCount = 0
		var pauseCount = 0
		var skipForwardIntervals: [Double] = []
		var skipBackwardIntervals: [Double] = []
		var positions: [TimeInterval] = []
		var rates: [Float] = []

		RemoteCommandWiring.install(
			center: center,
			play: {
				playCount += 1
				return true
			},
			pause: {
				pauseCount += 1
				return true
			},
			skipForward: { interval in
				skipForwardIntervals.append(interval)
				return true
			},
			skipBackward: { interval in
				skipBackwardIntervals.append(interval)
				return true
			},
			changePlaybackPosition: { position in
				positions.append(position)
				return true
			},
			changePlaybackRate: { rate in
				rates.append(rate)
				return true
			}
		)

		XCTAssertTrue(center.play.isEnabled)
		XCTAssertTrue(center.pause.isEnabled)
		XCTAssertEqual(center.skipForward.preferredIntervals, [30])
		XCTAssertEqual(center.skipBackward.preferredIntervals, [30])

		XCTAssertTrue(center.play.invoke())
		XCTAssertTrue(center.pause.invoke())
		XCTAssertTrue(center.skipForward.invoke(interval: 15))
		XCTAssertTrue(center.skipBackward.invoke(interval: 30))
		XCTAssertTrue(center.changePlaybackPosition.invoke(position: 12.5))
		XCTAssertTrue(center.changePlaybackRate.invoke(rate: 1.5))

		XCTAssertEqual(playCount, 1)
		XCTAssertEqual(pauseCount, 1)
		XCTAssertEqual(skipForwardIntervals, [15])
		XCTAssertEqual(skipBackwardIntervals, [30])
		XCTAssertEqual(positions, [12.5])
		XCTAssertEqual(rates, [1.5])
	}
}

private final class FakeRemoteCommandCenter: RemoteCommandCenterProtocol {
	let play = FakeRemoteCommand()
	let pause = FakeRemoteCommand()
	let skipForward = FakeSkipIntervalRemoteCommand()
	let skipBackward = FakeSkipIntervalRemoteCommand()
	let changePlaybackPosition = FakeChangePlaybackPositionRemoteCommand()
	let changePlaybackRate = FakeChangePlaybackRateRemoteCommand()
}

private final class FakeRemoteCommand: RemoteCommandProtocol {
	var isEnabled = false
	private var handler: (() -> Bool)?

	func addHandler(_ handler: @escaping () -> Bool) {
		self.handler = handler
	}

	func removeAllHandlers() {
		handler = nil
	}

	func invoke() -> Bool {
		handler?() ?? false
	}
}

private final class FakeSkipIntervalRemoteCommand: SkipIntervalRemoteCommandProtocol {
	var isEnabled = false
	var preferredIntervals: [NSNumber] = []
	private var handler: ((Double) -> Bool)?

	func addHandler(_ handler: @escaping (Double) -> Bool) {
		self.handler = handler
	}

	func removeAllHandlers() {
		handler = nil
	}

	func invoke(interval: Double) -> Bool {
		handler?(interval) ?? false
	}
}

private final class FakeChangePlaybackPositionRemoteCommand: ChangePlaybackPositionRemoteCommandProtocol {
	var isEnabled = false
	private var handler: ((TimeInterval) -> Bool)?

	func addHandler(_ handler: @escaping (TimeInterval) -> Bool) {
		self.handler = handler
	}

	func removeAllHandlers() {
		handler = nil
	}

	func invoke(position: TimeInterval) -> Bool {
		handler?(position) ?? false
	}
}

private final class FakeChangePlaybackRateRemoteCommand: ChangePlaybackRateRemoteCommandProtocol {
	var isEnabled = false
	private var handler: ((Float) -> Bool)?

	func addHandler(_ handler: @escaping (Float) -> Bool) {
		self.handler = handler
	}

	func removeAllHandlers() {
		handler = nil
	}

	func invoke(rate: Float) -> Bool {
		handler?(rate) ?? false
	}
}
