//
//  VoiceMessageRecorder.swift
//  Tyflocentrum
//
//  Created by Codex on 27/01/2026.
//

import AVFoundation
import Foundation

@MainActor
final class VoiceMessageRecorder: NSObject, ObservableObject {
	enum State: Equatable {
		case idle
		case recording
		case recorded
		case playingPreview
	}

	@Published private(set) var state: State = .idle
	@Published private(set) var elapsedTime: TimeInterval = 0
	@Published private(set) var recordedDurationMs: Int = 0
	@Published var shouldShowError = false
	@Published var errorMessage = ""

	private var recorder: AVAudioRecorder?
	private var previewPlayer: AVAudioPlayer?
	private var timer: Timer?
	private(set) var recordedFileURL: URL?

	var canSend: Bool {
		guard state == .recorded || state == .playingPreview else { return false }
		return recordedFileIsUsable()
	}

	override init() {
		super.init()
	}

	func startRecording(maxDurationSeconds: TimeInterval = 20 * 60, pausing audioPlayer: AudioPlayer? = nil) async {
		guard state != .recording else { return }

		stopPreviewIfNeeded()

		let hasPermission = await requestMicrophonePermission()
		guard hasPermission else {
			showError("Brak dostępu do mikrofonu. Włącz uprawnienia w Ustawieniach.")
			return
		}

		audioPlayer?.pause()

		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
			try session.setActive(true, options: [])

			let previousFileURL = recordedFileURL
			let fileURL = FileManager.default.temporaryDirectory
				.appendingPathComponent("voice-\(UUID().uuidString)")
				.appendingPathExtension("m4a")

			let settings: [String: Any] = [
				AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
				AVSampleRateKey: 44_100,
				AVNumberOfChannelsKey: 1,
				AVEncoderBitRateKey: 160_000,
				AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
			]

			let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
			recorder.delegate = self
			recorder.isMeteringEnabled = true
			recorder.prepareToRecord()

			self.recorder = recorder
			self.recordedFileURL = fileURL
			self.recordedDurationMs = 0
			self.elapsedTime = 0
			self.state = .recording
			if let previousFileURL, previousFileURL != fileURL {
				try? FileManager.default.removeItem(at: previousFileURL)
			}

			recorder.record(forDuration: maxDurationSeconds)
			startTimer { [weak self] in
				guard let self else { return }
				guard let recorder = self.recorder else { return }
				self.elapsedTime = recorder.currentTime
			}
		} catch {
			cleanupRecordingFile()
			showError("Nie udało się rozpocząć nagrywania.")
		}
	}

	func stopRecording() {
		guard state == .recording else { return }
		let elapsedTimeSnapshot = elapsedTime
		timer?.invalidate()
		timer = nil

		guard let recorder else {
			cleanupRecordingFile()
			state = .idle
			return
		}

		let durationSecondsSnapshot = recorder.currentTime
		recorder.stop()
		self.recorder = nil

		var durationSeconds = max(durationSecondsSnapshot, elapsedTimeSnapshot)
		if durationSeconds <= 0, let url = recordedFileURL {
			let asset = AVURLAsset(url: url)
			let assetSeconds = asset.duration.seconds
			if assetSeconds.isFinite, assetSeconds > 0 {
				durationSeconds = assetSeconds
			}
		}

		let durationMs = Int((durationSeconds * 1000.0).rounded())
		recordedDurationMs = max(0, durationMs)
		elapsedTime = durationSeconds
		state = recordedFileIsUsable() ? .recorded : .idle
	}

	private func recordedFileIsUsable() -> Bool {
		guard let url = recordedFileURL else { return false }
		let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		return fileSize > 0
	}

	func togglePreview() {
		switch state {
		case .playingPreview:
			stopPreviewIfNeeded()
			state = recordedFileIsUsable() ? .recorded : .idle
		case .recorded:
			startPreview()
		default:
			break
		}
	}

	func reset() {
		stopPreviewIfNeeded()
		stopRecording()
		cleanupRecordingFile()
		recordedDurationMs = 0
		elapsedTime = 0
		state = .idle
	}

	#if DEBUG
	func seedRecordedForUITesting(durationMs: Int = 5_000) {
		guard ProcessInfo.processInfo.arguments.contains("UI_TESTING") else { return }

		stopPreviewIfNeeded()
		timer?.invalidate()
		timer = nil

		recorder?.stop()
		recorder = nil

		cleanupRecordingFile()

		let fileURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("ui-test-voice-\(UUID().uuidString)")
			.appendingPathExtension("m4a")
		try? Data("UI_TEST_VOICE".utf8).write(to: fileURL, options: .atomic)

		recordedFileURL = fileURL
		recordedDurationMs = max(1, durationMs)
		elapsedTime = TimeInterval(recordedDurationMs) / 1000.0
		state = .recorded
	}
	#endif

	private func startPreview() {
		guard let url = recordedFileURL else { return }
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
			try session.setActive(true, options: [])

			let player = try AVAudioPlayer(contentsOf: url)
			player.delegate = self
			player.prepareToPlay()
			let didStart = player.play()
			guard didStart else {
				showError("Nie udało się rozpocząć odsłuchu nagrania.")
				return
			}
			previewPlayer = player
			state = .playingPreview

			startTimer { [weak self] in
				guard let self else { return }
				guard let player = self.previewPlayer else { return }
				self.elapsedTime = player.currentTime
			}
		} catch {
			showError("Nie udało się odtworzyć nagrania.")
		}
	}

	private func stopPreviewIfNeeded() {
		timer?.invalidate()
		timer = nil

		previewPlayer?.stop()
		previewPlayer = nil
	}

	private func startTimer(tick: @escaping () -> Void) {
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
			tick()
		}
	}

	private func cleanupRecordingFile() {
		if let url = recordedFileURL {
			try? FileManager.default.removeItem(at: url)
		}
		recordedFileURL = nil
	}

	private func requestMicrophonePermission() async -> Bool {
		let session = AVAudioSession.sharedInstance()
		return await withCheckedContinuation { continuation in
			session.requestRecordPermission { granted in
				continuation.resume(returning: granted)
			}
		}
	}

	private func showError(_ message: String) {
		errorMessage = message
		shouldShowError = true
	}
}

extension VoiceMessageRecorder: AVAudioRecorderDelegate {
	nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
		Task { @MainActor in
			guard self.recorder === recorder else { return }
			if flag {
				self.stopRecording()
			} else {
				self.cleanupRecordingFile()
				self.recordedDurationMs = 0
				self.elapsedTime = 0
				self.state = .idle
				self.showError("Nagrywanie nie powiodło się.")
			}
		}
	}
}

extension VoiceMessageRecorder: AVAudioPlayerDelegate {
	nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		Task { @MainActor in
			guard self.previewPlayer === player else { return }
			self.timer?.invalidate()
			self.timer = nil
			self.previewPlayer = nil
			self.elapsedTime = TimeInterval(self.recordedDurationMs) / 1000.0
			self.state = self.recordedFileIsUsable() ? .recorded : .idle
			if !flag {
				self.showError("Nie udało się odtworzyć nagrania.")
			}
		}
	}

	nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
		Task { @MainActor in
			guard self.previewPlayer === player else { return }
			self.stopPreviewIfNeeded()
			self.elapsedTime = TimeInterval(self.recordedDurationMs) / 1000.0
			self.state = self.recordedFileIsUsable() ? .recorded : .idle
			self.showError(error?.localizedDescription ?? "Nie udało się odtworzyć nagrania.")
		}
	}
}
