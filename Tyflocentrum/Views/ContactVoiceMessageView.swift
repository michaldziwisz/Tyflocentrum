//
//  ContactVoiceMessageView.swift
//  Tyflocentrum
//

import SwiftUI
import UIKit

struct ContactVoiceMessageView: View {
	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject var audioPlayer: AudioPlayer
	@EnvironmentObject var magicTapCoordinator: MagicTapCoordinator

	@StateObject private var viewModel = ContactViewModel()
	@StateObject private var voiceRecorder = VoiceMessageRecorder()

	private let onSent: () -> Void

	init(onSent: @escaping () -> Void = {}) {
		self.onSent = onSent
	}

	@State private var magicTapToken: UUID?
	@State private var startRecordingTask: Task<Void, Never>?
	@State private var recordingTrigger: RecordingTrigger?
	@State private var isEarModeEnabled = false
	@State private var isHoldingToTalk = false

	@AccessibilityFocusState private var focusedField: Field?

	private enum Field: Hashable {
		case name
	}

	private enum RecordingTrigger {
		case magicTap
		case holdToTalk
		case proximity
	}

	var body: some View {
		let hasName = !viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let canSendVoice = hasName && voiceRecorder.canSend && !viewModel.isSending
		let isRecording = voiceRecorder.state == .recording

		Form {
			Section {
				TextField("Imię", text: $viewModel.name)
					.textContentType(.name)
					.accessibilityIdentifier("contact.name")
					.accessibilityHint("Wpisz imię, które będzie widoczne przy wiadomości.")
					.accessibilityFocused($focusedField, equals: .name)
					.disabled(viewModel.isSending || isRecording)
			}

			Section("Nagrywanie") {
				Toggle("Nagrywaj po przyłożeniu telefonu do ucha", isOn: $isEarModeEnabled)
					.accessibilityIdentifier("contact.voice.earMode")
					.accessibilityHint(hasName ? "Gdy włączone, przyłożenie telefonu do ucha rozpoczyna nagrywanie, a oderwanie kończy." : "Najpierw uzupełnij imię, aby włączyć ten tryb.")
					.disabled(viewModel.isSending || voiceRecorder.state == .playingPreview || isRecording || !hasName)

				Text("Magic Tap: rozpocznij/zatrzymaj nagrywanie. Przytrzymaj przycisk i mów, aby nagrywać bez gadania VoiceOvera.")
					.font(.footnote)
					.foregroundColor(.secondary)
					.accessibilityIdentifier("contact.voice.instructions")

				HStack {
					Image(systemName: "mic.fill")
					Text(isHoldingToTalk ? "Mów… (puść, aby zakończyć)" : "Przytrzymaj i mów")
						.fontWeight(.semibold)
				}
				.frame(maxWidth: .infinity, minHeight: 56)
				.contentShape(Rectangle())
				.background(Color.accentColor.opacity(0.12))
				.cornerRadius(12)
				.onLongPressGesture(
					minimumDuration: 0.2,
					maximumDistance: 24,
					pressing: { pressing in
						isHoldingToTalk = pressing
						if !pressing {
							if recordingTrigger == .holdToTalk {
								stopRecording()
							}
						}
					},
					perform: {
						startRecording(trigger: .holdToTalk, announceBeforeStart: false)
					}
				)
				.accessibilityAddTraits(.isButton)
				.accessibilityIdentifier("contact.voice.holdToTalk")
				.accessibilityHint("Dwukrotnie stuknij i przytrzymaj, aby mówić. Puść, aby zakończyć.")
				.disabled(
					viewModel.isSending
						|| !hasName
						|| (voiceRecorder.state != .idle && recordingTrigger != .holdToTalk)
				)

				if isRecording {
					HStack {
						ProgressView()
						Text("Nagrywanie… \(formatTime(voiceRecorder.elapsedTime))")
					}
					.accessibilityElement(children: .combine)
					.accessibilityIdentifier("contact.voice.recordingStatus")

					Button("Zatrzymaj") {
						stopRecording()
					}
					.accessibilityIdentifier("contact.voice.stop")
					.accessibilityHint("Zatrzymuje nagrywanie. Możesz też użyć Magic Tap lub oderwać telefon od ucha.")
					.disabled(viewModel.isSending)
				}
			}

			if voiceRecorder.state == .recorded || voiceRecorder.state == .playingPreview {
				Section("Nagranie") {
					Text("Długość: \(formatTime(TimeInterval(voiceRecorder.recordedDurationMs) / 1000.0))")
						.accessibilityIdentifier("contact.voice.duration")

					Button(voiceRecorder.state == .playingPreview ? "Zatrzymaj odsłuch" : "Odsłuchaj") {
						voiceRecorder.togglePreview()
					}
					.accessibilityIdentifier("contact.voice.preview")
					.accessibilityHint("Odtwarza nagraną głosówkę.")
					.disabled(viewModel.isSending)

					Button("Usuń nagranie", role: .destructive) {
						resetRecording()
						UIAccessibility.post(notification: .announcement, argument: "Nagranie usunięte")
					}
					.accessibilityIdentifier("contact.voice.delete")
					.accessibilityHint("Usuwa nagraną głosówkę.")
					.disabled(viewModel.isSending)

					Button {
						Task { @MainActor in
							guard let url = voiceRecorder.recordedFileURL else { return }
							let didSend = await viewModel.sendVoice(using: api, audioFileURL: url, durationMs: voiceRecorder.recordedDurationMs)
							guard didSend else { return }

							resetRecording()
							UIAccessibility.post(notification: .announcement, argument: "Głosówka wysłana pomyślnie")
							onSent()
						}
					} label: {
						if viewModel.isSending {
							HStack {
								ProgressView()
								Text("Wysyłanie…")
							}
							.accessibilityElement(children: .combine)
						}
						else {
							Text("Wyślij głosówkę")
						}
					}
					.disabled(!canSendVoice)
					.accessibilityIdentifier("contact.voice.send")
					.accessibilityHint(canSendVoice ? "Wysyła głosówkę do redakcji." : "Wpisz imię i nagraj głosówkę, aby wysłać.")
				}
			}
		}
		.accessibilityIdentifier("contactVoice.form")
		.navigationTitle("Głosówka")
		.navigationBarTitleDisplayMode(.inline)
		.alert("Błąd", isPresented: $viewModel.shouldShowError) {
			Button("OK") {}
		} message: {
			Text(viewModel.errorMessage)
		}
		.alert("Błąd", isPresented: $voiceRecorder.shouldShowError) {
			Button("OK") {}
		} message: {
			Text(voiceRecorder.errorMessage)
		}
		.task {
			focusedField = .name
			#if DEBUG
			if ProcessInfo.processInfo.arguments.contains("UI_TESTING_SEED_VOICE_RECORDED") {
				voiceRecorder.seedRecordedForUITesting()
			}
			#endif
		}
		.onAppear {
			registerMagicTapOverrideIfNeeded()
		}
		.onDisappear {
			unregisterMagicTapOverride()
			disableProximityMonitoring()
			resetRecording()
		}
		.onChange(of: isEarModeEnabled) { enabled in
			if enabled {
				enableProximityMonitoring()
			} else {
				disableProximityMonitoring()
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
			guard isEarModeEnabled else { return }
			handleProximityChange()
		}
	}

	private func registerMagicTapOverrideIfNeeded() {
		guard magicTapToken == nil else { return }
		magicTapToken = magicTapCoordinator.push {
			handleMagicTap()
		}
	}

	private func unregisterMagicTapOverride() {
		if let magicTapToken {
			magicTapCoordinator.remove(magicTapToken)
			self.magicTapToken = nil
		}
	}

	private func handleMagicTap() -> Bool {
		guard !viewModel.isSending else { return true }

		switch voiceRecorder.state {
		case .recording:
			stopRecording()
		case .idle:
			startRecording(trigger: .magicTap, announceBeforeStart: true)
		case .recorded, .playingPreview:
			if UIAccessibility.isVoiceOverRunning {
				UIAccessibility.post(notification: .announcement, argument: "Nagranie jest gotowe. Usuń je, aby nagrać nowe.")
			}
		}
		return true
	}

	private func startRecording(trigger: RecordingTrigger, announceBeforeStart: Bool) {
		guard voiceRecorder.state == .idle else { return }
		guard !viewModel.isSending else { return }
		guard !viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			viewModel.errorMessage = "Uzupełnij imię, aby nagrać głosówkę."
			viewModel.shouldShowError = true
			return
		}

		recordingTrigger = trigger
		startRecordingTask?.cancel()

		audioPlayer.pause()

		startRecordingTask = Task { @MainActor in
			if trigger == .magicTap {
				let announcement = "Nagrywaj wiadomość po sygnale."
				if announceBeforeStart, UIAccessibility.isVoiceOverRunning {
					UIAccessibility.post(notification: .announcement, argument: announcement)
					await waitForVoiceOverAnnouncementToFinish(announcement)
					guard !Task.isCancelled else { return }
				}

				AudioCuePlayer.shared.playStartCue()
				let cueDelay = AudioCuePlayer.shared.startCueDurationSeconds + 0.1
				try? await Task.sleep(nanoseconds: UInt64(cueDelay * 1_000_000_000))
				guard !Task.isCancelled else { return }
			}

			await voiceRecorder.startRecording(pausing: audioPlayer)

			if voiceRecorder.state == .recording {
				switch trigger {
				case .magicTap, .proximity:
					playHaptic(times: 2)
				case .holdToTalk:
					playHaptic(times: 1)
				}
			} else {
				recordingTrigger = nil
			}
		}
	}

	private func stopRecording() {
		let trigger = recordingTrigger
		startRecordingTask?.cancel()
		startRecordingTask = nil

		if voiceRecorder.state == .recording {
			voiceRecorder.stopRecording()
		}
		recordingTrigger = nil
		playHaptic(times: 1)
		if trigger == .magicTap {
			AudioCuePlayer.shared.playStopCue()
		}
	}

	private func resetRecording() {
		startRecordingTask?.cancel()
		startRecordingTask = nil
		recordingTrigger = nil
		voiceRecorder.reset()
	}

	private func enableProximityMonitoring() {
		UIDevice.current.isProximityMonitoringEnabled = true
		handleProximityChange()
	}

	private func disableProximityMonitoring() {
		UIDevice.current.isProximityMonitoringEnabled = false
	}

	private func handleProximityChange() {
		let isNear = UIDevice.current.proximityState

		if isNear {
			guard voiceRecorder.state == .idle else { return }
			guard recordingTrigger == nil else { return }
			startRecording(trigger: .proximity, announceBeforeStart: false)
		} else {
			guard recordingTrigger == .proximity else { return }
			stopRecording()
		}
	}

	private func formatTime(_ seconds: TimeInterval) -> String {
		guard seconds.isFinite, seconds > 0 else { return "00:00" }
		let total = Int(seconds.rounded(.down))
		let m = total / 60
		let s = total % 60
		return String(format: "%02d:%02d", m, s)
	}

	private func waitForVoiceOverAnnouncementToFinish(_ announcement: String) async {
		guard UIAccessibility.isVoiceOverRunning else { return }
		do {
			try await withTimeout(5) {
				for await notification in NotificationCenter.default.notifications(named: UIAccessibility.announcementDidFinishNotification) {
					guard !Task.isCancelled else { return }
					let finishedAnnouncement = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
					guard finishedAnnouncement == announcement else { continue }
					return
				}
			}
		} catch {
			// Best-effort: if we can't observe completion, continue after timeout.
		}
	}

	private func playHaptic(times: Int) {
		guard times > 0 else { return }
		let generator = UIImpactFeedbackGenerator(style: .light)
		generator.prepare()
		generator.impactOccurred()

		guard times > 1 else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
			generator.prepare()
			generator.impactOccurred()
		}
	}
}
