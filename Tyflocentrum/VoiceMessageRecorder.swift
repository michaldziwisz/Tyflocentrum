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
		state == .recorded && recordedFileURL != nil && recordedDurationMs > 0
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
		timer?.invalidate()
		timer = nil

		guard let recorder else {
			cleanupRecordingFile()
			state = .idle
			return
		}

		recorder.stop()
		self.recorder = nil

		let durationSeconds = recorder.currentTime
		let durationMs = Int((durationSeconds * 1000.0).rounded())
		self.recordedDurationMs = max(0, durationMs)
		self.elapsedTime = durationSeconds
		self.state = (recordedDurationMs > 0) ? .recorded : .idle
	}

	func togglePreview() {
		switch state {
		case .playingPreview:
			stopPreviewIfNeeded()
			if recordedDurationMs > 0 {
				state = .recorded
			} else {
				state = .idle
			}
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

	private func startPreview() {
		guard let url = recordedFileURL else { return }
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
			try session.setActive(true, options: [])

			let player = try AVAudioPlayer(contentsOf: url)
			player.prepareToPlay()
			player.play()
			previewPlayer = player
			state = .playingPreview

			startTimer { [weak self] in
				guard let self else { return }
				guard let player = self.previewPlayer else { return }
				self.elapsedTime = player.currentTime
				if !player.isPlaying {
					self.stopPreviewIfNeeded()
					self.state = .recorded
				}
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
