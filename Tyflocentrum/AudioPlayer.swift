//
//  AudioPlayer.swift
//  Tyflocentrum
//
//  Replaced BASS-based playback with AVPlayer.
//

import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: ObservableObject {
	@Published private(set) var isPlaying = false
	@Published private(set) var currentURL: URL?

	private let player: AVPlayer
	private var timeControlStatusObserver: NSKeyValueObservation?

	init(player: AVPlayer = AVPlayer()) {
		self.player = player

		timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
			guard let self else { return }
			Task { @MainActor in
				self.isPlaying = player.timeControlStatus == .playing
			}
		}
	}

	func play(url: URL) {
		configureAudioSessionForPlayback()

		if currentURL != url {
			currentURL = url
			player.replaceCurrentItem(with: AVPlayerItem(url: url))
		}

		player.play()
	}

	func pause() {
		player.pause()
	}

	func stop() {
		player.pause()
		player.replaceCurrentItem(with: nil)
		currentURL = nil
	}

	func togglePlayPause(url: URL) {
		if currentURL != url {
			play(url: url)
			return
		}

		if isPlaying {
			pause()
		} else {
			player.play()
		}
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
}
