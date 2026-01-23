//
//  AudioPlayer.swift
//  Tyflocentrum
//
//  Replaced BASS-based playback with AVPlayer.
//

import AVFoundation
import Foundation
import MediaPlayer

enum PlaybackRatePolicy {
	static let supportedRates: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]

	static func next(after rate: Float) -> Float {
		guard !supportedRates.isEmpty else { return rate }
		let currentIndex = supportedRates.firstIndex(of: rate) ?? 0
		let nextIndex = supportedRates.index(after: currentIndex)
		return nextIndex < supportedRates.endIndex ? supportedRates[nextIndex] : supportedRates[0]
	}
}

struct ResumePositionStore {
	private let userDefaults: UserDefaults
	private let now: () -> Date
	private let throttleInterval: TimeInterval
	private var lastSave: Date

	init(
		userDefaults: UserDefaults,
		now: @escaping () -> Date = { Date() },
		throttleInterval: TimeInterval = 5,
		lastSave: Date = .distantPast
	) {
		self.userDefaults = userDefaults
		self.now = now
		self.throttleInterval = throttleInterval
		self.lastSave = lastSave
	}

	static func makeKey(for url: URL) -> String {
		"resume.\(url.absoluteString)"
	}

	func load(forKey key: String?) -> Double? {
		guard let key else { return nil }
		guard let saved = userDefaults.object(forKey: key) as? Double else { return nil }
		guard saved > 1 else { return nil }
		return saved
	}

	mutating func maybeSave(_ seconds: Double, forKey key: String?) {
		guard let key else { return }
		guard seconds.isFinite else { return }

		let currentTime = now()
		guard currentTime.timeIntervalSince(lastSave) >= throttleInterval else { return }
		lastSave = currentTime

		userDefaults.set(seconds, forKey: key)
	}

	func save(_ seconds: Double, forKey key: String?) {
		guard let key else { return }
		guard seconds.isFinite else { return }
		userDefaults.set(seconds, forKey: key)
	}

	func clear(forKey key: String?) {
		guard let key else { return }
		userDefaults.removeObject(forKey: key)
	}
}

@MainActor
final class AudioPlayer: ObservableObject {
	@Published private(set) var isPlaying = false
	@Published private(set) var currentURL: URL?
	@Published private(set) var currentTitle: String?
	@Published private(set) var currentSubtitle: String?
	@Published private(set) var isLiveStream = false
	@Published private(set) var playbackRate: Float = 1.0
	@Published private(set) var elapsedTime: TimeInterval = 0
	@Published private(set) var duration: TimeInterval?

	private let player: AVPlayer
	private var resumeStore: ResumePositionStore
	private var timeControlStatusObserver: NSKeyValueObservation?
	private var periodicTimeObserver: Any?
	private var endObserver: NSObjectProtocol?
	private var interruptionObserver: NSObjectProtocol?
	private var currentItemStatusObserver: NSKeyValueObservation?

	private var resumeKey: String?

	init(player: AVPlayer = AVPlayer(), userDefaults: UserDefaults = .standard) {
		self.player = player
		self.resumeStore = ResumePositionStore(userDefaults: userDefaults)
		player.automaticallyWaitsToMinimizeStalling = true

		timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
			guard let self else { return }
			Task { @MainActor in
				self.isPlaying = player.timeControlStatus == .playing
				self.updateNowPlayingPlaybackInfo()
			}
		}

		setupRemoteCommands()
		setupNotifications()
		setupPeriodicTimeObserver()
	}

	deinit {
		if let periodicTimeObserver {
			player.removeTimeObserver(periodicTimeObserver)
		}

		if let endObserver {
			NotificationCenter.default.removeObserver(endObserver)
		}

		if let interruptionObserver {
			NotificationCenter.default.removeObserver(interruptionObserver)
		}

		tearDownRemoteCommands()
		timeControlStatusObserver = nil
		currentItemStatusObserver = nil
	}

	func play(url: URL, title: String? = nil, subtitle: String? = nil, isLiveStream: Bool = false) {
		configureAudioSessionForPlayback()

		if currentURL != url {
			persistCurrentPositionIfNeeded()

			currentURL = url
			currentTitle = title
			currentSubtitle = subtitle
			self.isLiveStream = isLiveStream
			resumeKey = isLiveStream ? nil : ResumePositionStore.makeKey(for: url)

			player.replaceCurrentItem(with: AVPlayerItem(url: url))
			restoreResumePositionIfNeeded()

			updateRemoteCommandAvailability()
			updateNowPlayingMetadata()
		}

		if isLiveStream {
			playbackRate = 1.0
			player.play()
		} else {
			player.playImmediately(atRate: playbackRate)
		}
	}

	func pause() {
		player.pause()
		persistCurrentPositionIfNeeded()
		updateNowPlayingPlaybackInfo()
	}

	func stop() {
		persistCurrentPositionIfNeeded()
		player.pause()
		player.replaceCurrentItem(with: nil)
		currentURL = nil
		currentTitle = nil
		currentSubtitle = nil
		isLiveStream = false
		elapsedTime = 0
		duration = nil
		resumeKey = nil

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
		MPNowPlayingInfoCenter.default().playbackState = .stopped
		updateRemoteCommandAvailability()
	}

	func togglePlayPause(url: URL, title: String? = nil, subtitle: String? = nil, isLiveStream: Bool = false) {
		if currentURL != url {
			play(url: url, title: title, subtitle: subtitle, isLiveStream: isLiveStream)
			return
		}

		if isPlaying {
			pause()
		} else {
			if self.isLiveStream {
				player.play()
			} else {
				player.playImmediately(atRate: playbackRate)
			}
			updateNowPlayingPlaybackInfo()
		}
	}

	func skipForward(seconds: Double = 30) {
		seek(by: seconds)
	}

	func skipBackward(seconds: Double = 30) {
		seek(by: -seconds)
	}

	func seek(to seconds: Double) {
		guard !isLiveStream else { return }
		guard seconds.isFinite else { return }
		let clamped = max(0, seconds)
		player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
		updateNowPlayingPlaybackInfo()
	}

	func cyclePlaybackRate() {
		guard !isLiveStream else { return }
		setPlaybackRate(PlaybackRatePolicy.next(after: playbackRate))
	}

	func setPlaybackRate(_ rate: Float) {
		guard !isLiveStream else { return }
		playbackRate = rate
		if isPlaying {
			player.rate = rate
		}
		updateNowPlayingPlaybackInfo()
	}

	private func configureAudioSessionForPlayback() {
		let session = AVAudioSession.sharedInstance()
		do {
			try session.setCategory(.playback, mode: .default)
			try session.setActive(true)
		} catch {
			// No-op: audio may still play, but without preferred session behavior.
		}
	}

	private func seek(by deltaSeconds: Double) {
		guard !isLiveStream else { return }
		guard let currentItem = player.currentItem else { return }
		guard currentItem.status == .readyToPlay else { return }

		let currentSeconds = elapsedTime
		let target = max(0, currentSeconds + deltaSeconds)
		seek(to: target)
	}

	private func setupPeriodicTimeObserver() {
		let interval = CMTime(seconds: 1, preferredTimescale: 2)
		periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
			guard let self else { return }
			let seconds = time.seconds
			if seconds.isFinite {
				self.elapsedTime = seconds
			}

			let durationSeconds = self.player.currentItem?.duration.seconds
			if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
				self.duration = durationSeconds
			} else {
				self.duration = nil
			}

			self.maybePersistResumeTime(seconds)
			self.updateNowPlayingPlaybackInfo()
		}
	}

	private func setupNotifications() {
		interruptionObserver = NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: AVAudioSession.sharedInstance(),
			queue: .main
		) { [weak self] notification in
			guard let self else { return }
			guard let userInfo = notification.userInfo,
				  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
				  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
			else {
				return
			}

			switch type {
			case .began:
				self.pause()
			case .ended:
				let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
				let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
				if options.contains(.shouldResume), self.currentURL != nil {
					if self.isLiveStream {
						self.player.play()
					} else {
						self.player.playImmediately(atRate: self.playbackRate)
					}
				}
			@unknown default:
				break
			}
		}

		endObserver = NotificationCenter.default.addObserver(
			forName: .AVPlayerItemDidPlayToEndTime,
			object: nil,
			queue: .main
		) { [weak self] notification in
			guard let self else { return }
			guard let item = notification.object as? AVPlayerItem else { return }
			guard item === self.player.currentItem else { return }

			self.isPlaying = false
			if let resumeKey = self.resumeKey {
				self.resumeStore.clear(forKey: resumeKey)
			}
			self.updateNowPlayingPlaybackInfo()
		}
	}

	private func setupRemoteCommands() {
		let commandCenter = MPRemoteCommandCenter.shared()

		commandCenter.playCommand.addTarget { [weak self] _ in
			guard let self else { return .commandFailed }
			Task { @MainActor in
				guard self.currentURL != nil else { return }
				self.configureAudioSessionForPlayback()
				if self.isLiveStream {
					self.player.play()
				} else {
					self.player.playImmediately(atRate: self.playbackRate)
				}
				self.updateNowPlayingPlaybackInfo()
			}
			return .success
		}

		commandCenter.pauseCommand.addTarget { [weak self] _ in
			guard let self else { return .commandFailed }
			Task { @MainActor in
				self.pause()
			}
			return .success
		}

		commandCenter.skipForwardCommand.preferredIntervals = [30]
		commandCenter.skipForwardCommand.addTarget { [weak self] _ in
			guard let self else { return .commandFailed }
			Task { @MainActor in
				self.skipForward(seconds: 30)
			}
			return .success
		}

		commandCenter.skipBackwardCommand.preferredIntervals = [30]
		commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
			guard let self else { return .commandFailed }
			Task { @MainActor in
				self.skipBackward(seconds: 30)
			}
			return .success
		}

		commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
			guard let self else { return .commandFailed }
			guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
			Task { @MainActor in
				self.seek(to: event.positionTime)
			}
			return .success
		}

		commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
			guard let self else { return .commandFailed }
			guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
			Task { @MainActor in
				self.setPlaybackRate(event.playbackRate)
			}
			return .success
		}

		commandCenter.playCommand.isEnabled = true
		commandCenter.pauseCommand.isEnabled = true
		updateRemoteCommandAvailability()
	}

	nonisolated private func tearDownRemoteCommands() {
		let commandCenter = MPRemoteCommandCenter.shared()
		commandCenter.playCommand.removeTarget(nil)
		commandCenter.pauseCommand.removeTarget(nil)
		commandCenter.skipForwardCommand.removeTarget(nil)
		commandCenter.skipBackwardCommand.removeTarget(nil)
		commandCenter.changePlaybackPositionCommand.removeTarget(nil)
		commandCenter.changePlaybackRateCommand.removeTarget(nil)
	}

	private func updateRemoteCommandAvailability() {
		let commandCenter = MPRemoteCommandCenter.shared()

		let hasItem = currentURL != nil
		commandCenter.playCommand.isEnabled = hasItem
		commandCenter.pauseCommand.isEnabled = hasItem

		let seekable = hasItem && !isLiveStream
		commandCenter.skipForwardCommand.isEnabled = seekable
		commandCenter.skipBackwardCommand.isEnabled = seekable
		commandCenter.changePlaybackPositionCommand.isEnabled = seekable
		commandCenter.changePlaybackRateCommand.isEnabled = seekable
	}

	private func updateNowPlayingMetadata() {
		var info: [String: Any] = [:]

		if let currentTitle, !currentTitle.isEmpty {
			info[MPMediaItemPropertyTitle] = currentTitle
		}

		if let currentSubtitle, !currentSubtitle.isEmpty {
			info[MPMediaItemPropertyArtist] = currentSubtitle
		}

		info[MPNowPlayingInfoPropertyIsLiveStream] = isLiveStream

		MPNowPlayingInfoCenter.default().nowPlayingInfo = info
		updateNowPlayingPlaybackInfo()
	}

	private func updateNowPlayingPlaybackInfo() {
		guard currentURL != nil else { return }

		var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

		if !isLiveStream {
			info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
			if let duration {
				info[MPMediaItemPropertyPlaybackDuration] = duration
			}
			info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
		} else {
			info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = info
		MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
	}

	private func restoreResumePositionIfNeeded() {
		guard let saved = resumeStore.load(forKey: resumeKey) else { return }

		currentItemStatusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
			guard let self else { return }
			guard item.status == .readyToPlay else { return }

			Task { @MainActor in
				self.seek(to: saved)
				self.currentItemStatusObserver = nil
			}
		}
	}

	private func maybePersistResumeTime(_ seconds: Double) {
		guard !isLiveStream else { return }
		resumeStore.maybeSave(seconds, forKey: resumeKey)
	}

	private func persistCurrentPositionIfNeeded() {
		guard !isLiveStream else { return }
		resumeStore.save(elapsedTime, forKey: resumeKey)
	}
}
