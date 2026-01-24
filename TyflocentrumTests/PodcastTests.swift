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

	func testPreviousPlaybackRateCyclesBackward() {
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 2.0), 1.75)
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 1.75), 1.5)
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 1.5), 1.25)
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 1.25), 1.0)
	}

	func testPreviousPlaybackRateWrapsToEnd() {
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 1.0), 2.0)
	}

	func testPreviousPlaybackRateTreatsUnknownAsLast() {
		XCTAssertEqual(PlaybackRatePolicy.previous(before: 1.33), 2.0)
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

final class SafeHTMLViewTests: XCTestCase {
	func testMakeDocumentWrapsBodyAndAddsCSP() {
		let body = "<h1>Test</h1><p>Ala ma kota</p>"
		let document = SafeHTMLView.makeDocument(body: body, fontSize: 17, languageCode: "pl")

		XCTAssertTrue(document.contains("<!doctype html>"))
		XCTAssertTrue(document.contains("<html lang=\"pl\">"))
		XCTAssertTrue(document.contains(body))
		XCTAssertTrue(document.contains("Content-Security-Policy"))
		XCTAssertTrue(document.contains("default-src 'none'"))
		XCTAssertTrue(document.contains("frame-src 'none'"))
		XCTAssertTrue(document.contains("form-action 'none'"))
	}

	func testAllowedSchemesPreventUnsafeNavigation() {
		XCTAssertTrue(SafeHTMLView.isAllowedWebViewScheme("https"))
		XCTAssertTrue(SafeHTMLView.isAllowedWebViewScheme("http"))
		XCTAssertTrue(SafeHTMLView.isAllowedWebViewScheme("about"))
		XCTAssertFalse(SafeHTMLView.isAllowedWebViewScheme("file"))
		XCTAssertFalse(SafeHTMLView.isAllowedWebViewScheme("javascript"))

		XCTAssertTrue(SafeHTMLView.isAllowedExternalScheme("https"))
		XCTAssertTrue(SafeHTMLView.isAllowedExternalScheme("mailto"))
		XCTAssertTrue(SafeHTMLView.isAllowedExternalScheme("tel"))
		XCTAssertFalse(SafeHTMLView.isAllowedExternalScheme("file"))
		XCTAssertFalse(SafeHTMLView.isAllowedExternalScheme("data"))
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
		XCTAssertEqual(center.skipForwardPreferredIntervals, [30])
		XCTAssertEqual(center.skipBackwardPreferredIntervals, [30])

		XCTAssertTrue(center.invokePlay())
		XCTAssertTrue(center.invokePause())
		XCTAssertTrue(center.invokeSkipForward(interval: 15))
		XCTAssertTrue(center.invokeSkipBackward(interval: 30))
		XCTAssertTrue(center.invokeChangePlaybackPosition(position: 12.5))
		XCTAssertTrue(center.invokeChangePlaybackRate(rate: 1.5))

		XCTAssertEqual(playCount, 1)
		XCTAssertEqual(pauseCount, 1)
		XCTAssertEqual(skipForwardIntervals, [15])
		XCTAssertEqual(skipBackwardIntervals, [30])
		XCTAssertEqual(positions, [12.5])
		XCTAssertEqual(rates, [1.5])
	}
}

private final class FakeRemoteCommandCenter: RemoteCommandCenterProtocol {
	private let playCommand = FakeRemoteCommand()
	private let pauseCommand = FakeRemoteCommand()
	private let skipForwardCommand = FakeSkipIntervalRemoteCommand()
	private let skipBackwardCommand = FakeSkipIntervalRemoteCommand()
	private let changePlaybackPositionCommand = FakeChangePlaybackPositionRemoteCommand()
	private let changePlaybackRateCommand = FakeChangePlaybackRateRemoteCommand()

	var play: RemoteCommandProtocol { playCommand }
	var pause: RemoteCommandProtocol { pauseCommand }
	var skipForward: SkipIntervalRemoteCommandProtocol { skipForwardCommand }
	var skipBackward: SkipIntervalRemoteCommandProtocol { skipBackwardCommand }
	var changePlaybackPosition: ChangePlaybackPositionRemoteCommandProtocol { changePlaybackPositionCommand }
	var changePlaybackRate: ChangePlaybackRateRemoteCommandProtocol { changePlaybackRateCommand }

	@discardableResult
	func invokePlay() -> Bool { playCommand.invoke() }
	@discardableResult
	func invokePause() -> Bool { pauseCommand.invoke() }
	@discardableResult
	func invokeSkipForward(interval: Double) -> Bool { skipForwardCommand.invoke(interval: interval) }
	@discardableResult
	func invokeSkipBackward(interval: Double) -> Bool { skipBackwardCommand.invoke(interval: interval) }
	@discardableResult
	func invokeChangePlaybackPosition(position: TimeInterval) -> Bool { changePlaybackPositionCommand.invoke(position: position) }
	@discardableResult
	func invokeChangePlaybackRate(rate: Float) -> Bool { changePlaybackRateCommand.invoke(rate: rate) }

	var skipForwardPreferredIntervals: [NSNumber] { skipForwardCommand.preferredIntervals }
	var skipBackwardPreferredIntervals: [NSNumber] { skipBackwardCommand.preferredIntervals }
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

@MainActor
final class AsyncListViewModelTests: XCTestCase {
	func testLoadIfNeededFetchesOnce() async {
		let viewModel = AsyncListViewModel<Int>()
		var fetchCount = 0

		let fetch: () async -> [Int] = {
			fetchCount += 1
			return [fetchCount]
		}

		await viewModel.loadIfNeeded(fetch)
		await viewModel.loadIfNeeded(fetch)

		XCTAssertEqual(fetchCount, 1)
		XCTAssertEqual(viewModel.items, [1])
		XCTAssertTrue(viewModel.hasLoaded)
		XCTAssertFalse(viewModel.isLoading)
	}

	func testRefreshFetchesAgain() async {
		let viewModel = AsyncListViewModel<Int>()
		var fetchCount = 0

		let fetch: () async -> [Int] = {
			fetchCount += 1
			return [fetchCount]
		}

		await viewModel.loadIfNeeded(fetch)
		await viewModel.refresh(fetch)

		XCTAssertEqual(fetchCount, 2)
		XCTAssertEqual(viewModel.items, [2])
		XCTAssertTrue(viewModel.hasLoaded)
		XCTAssertFalse(viewModel.isLoading)
	}

	func testLoadSkipsWhenAlreadyLoading() async {
		let viewModel = AsyncListViewModel<Int>()
		var fetchCount = 0
		var releaseFetch: CheckedContinuation<Void, Never>?

		let fetch: () async -> [Int] = {
			fetchCount += 1
			await withCheckedContinuation { continuation in
				releaseFetch = continuation
			}
			return [fetchCount]
		}

		let firstLoad = Task { await viewModel.load(fetch) }
		while releaseFetch == nil {
			await Task.yield()
		}

		await viewModel.load(fetch)
		releaseFetch?.resume()
		await firstLoad.value

		XCTAssertEqual(fetchCount, 1)
		XCTAssertEqual(viewModel.items, [1])
		XCTAssertTrue(viewModel.hasLoaded)
		XCTAssertFalse(viewModel.isLoading)
	}

	func testLoadSetsErrorMessageOnFailure() async {
		struct TestError: Error {}

		let viewModel = AsyncListViewModel<Int>()
		await viewModel.load {
			throw TestError()
		}

		XCTAssertTrue(viewModel.hasLoaded)
		XCTAssertTrue(viewModel.items.isEmpty)
		XCTAssertEqual(viewModel.errorMessage, "Nie udało się pobrać danych. Spróbuj ponownie.")
	}
}

@MainActor
final class ContactViewModelTests: XCTestCase {
	override func tearDown() {
		StubURLProtocol.requestHandler = nil
		super.tearDown()
	}

	func testCanSendRequiresNameAndMessage() {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let viewModel = ContactViewModel(userDefaults: defaults)
		viewModel.name = " "
		viewModel.message = " "
		XCTAssertFalse(viewModel.canSend)

		viewModel.name = "Ala"
		viewModel.message = "Test"
		XCTAssertTrue(viewModel.canSend)
	}

	func testSendShowsErrorWhenAPIReportsFailure() async {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		StubURLProtocol.requestHandler = { request in
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			let data = #"{"author":"UI","comment":"Test","error":"Błąd wysyłki"}"#.data(using: .utf8) ?? Data()
			return (response, data)
		}

		let api = TyfloAPI(session: makeSession())
		let viewModel = ContactViewModel(userDefaults: defaults)
		viewModel.name = "UI"
		viewModel.message = "Wiadomość"

		let didSend = await viewModel.send(using: api)

		XCTAssertFalse(didSend)
		XCTAssertTrue(viewModel.shouldShowError)
		XCTAssertEqual(viewModel.errorMessage, "Błąd wysyłki")
		XCTAssertFalse(viewModel.isSending)
	}

	func testSendResetsMessageOnSuccess() async {
		let suiteName = "TyflocentrumTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }

		StubURLProtocol.requestHandler = { request in
			let url = try XCTUnwrap(request.url)
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
			let data = #"{"author":"UI","comment":"Test","error":null}"#.data(using: .utf8) ?? Data()
			return (response, data)
		}

		let api = TyfloAPI(session: makeSession())
		let viewModel = ContactViewModel(userDefaults: defaults)
		viewModel.name = "UI"
		viewModel.message = "Wiadomość"

		let didSend = await viewModel.send(using: api)

		XCTAssertTrue(didSend)
		XCTAssertFalse(viewModel.shouldShowError)
		XCTAssertEqual(viewModel.message, "\nWysłane przy pomocy aplikacji Tyflocentrum")
		XCTAssertFalse(viewModel.isSending)
	}

	private func makeSession() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: config)
	}
}
