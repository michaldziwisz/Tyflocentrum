//
//  ContactView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 23/11/2022.
//

import Foundation
import SwiftUI

@MainActor
final class ContactViewModel: ObservableObject {
	private static let defaultMessage = "\nWysłane przy pomocy aplikacji Tyflocentrum"
	private static let nameKey = "name"
	private static let messageKey = "CurrentMSG"
	private static let fallbackErrorMessage = "Nie udało się wysłać wiadomości. Spróbuj ponownie."
	private static let fallbackVoiceErrorMessage = "Nie udało się wysłać głosówki. Spróbuj ponownie."

	@Published var name: String {
		didSet { userDefaults.set(name, forKey: Self.nameKey) }
	}

	@Published var message: String {
		didSet { userDefaults.set(message, forKey: Self.messageKey) }
	}

	@Published private(set) var isSending = false
	@Published var shouldShowError = false
	@Published var errorMessage = ""

	private let userDefaults: UserDefaults

	init(userDefaults: UserDefaults = .standard) {
		self.userDefaults = userDefaults
		self.name = userDefaults.string(forKey: Self.nameKey) ?? ""
		self.message = userDefaults.string(forKey: Self.messageKey) ?? Self.defaultMessage
		if message.isEmpty {
			message = Self.defaultMessage
		}

		#if DEBUG
		if ProcessInfo.processInfo.arguments.contains("UI_TESTING_CONTACT_MESSAGE_WHITESPACE") {
			message = " "
		}
		#endif
	}

	var canSend: Bool {
		!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	func send(using api: TyfloAPI) async -> Bool {
		guard canSend else { return false }
		guard !isSending else { return false }

		isSending = true
		defer { isSending = false }

		let (success, error) = await api.contactRadio(as: name, with: message)
		guard success else {
			errorMessage = error ?? Self.fallbackErrorMessage
			shouldShowError = true
			return false
		}

		message = Self.defaultMessage
		return true
	}

	func sendVoice(using api: TyfloAPI, audioFileURL: URL, durationMs: Int) async -> Bool {
		guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			errorMessage = "Uzupełnij imię, aby wysłać głosówkę."
			shouldShowError = true
			return false
		}
		guard !isSending else { return false }

		isSending = true
		defer { isSending = false }

		let (success, error) = await api.contactRadioVoice(as: name, audioFileURL: audioFileURL, durationMs: durationMs)
		guard success else {
			errorMessage = error ?? Self.fallbackVoiceErrorMessage
			shouldShowError = true
			return false
		}

		return true
	}
}

struct ContactView: View {
	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject var audioPlayer: AudioPlayer
	@Environment(\.dismiss) var dismiss
	@StateObject private var viewModel = ContactViewModel()
	@StateObject private var voiceRecorder = VoiceMessageRecorder()
	@AccessibilityFocusState private var focusedField: Field?

	private enum Field: Hashable {
		case name
		case message
	}

	var body: some View {
		let canSend = viewModel.canSend
		let canSendVoice = !viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && voiceRecorder.canSend
		NavigationView {
			Form {
				Section {
					TextField("Imię", text: $viewModel.name)
						.textContentType(.name)
						.accessibilityIdentifier("contact.name")
						.accessibilityHint("Wpisz imię, które będzie widoczne przy wiadomości.")
						.accessibilityFocused($focusedField, equals: .name)
					TextEditor(text: $viewModel.message)
						.accessibilityLabel("Wiadomość")
						.accessibilityIdentifier("contact.message")
						.accessibilityHint("Wpisz treść wiadomości do redakcji.")
						.accessibilityFocused($focusedField, equals: .message)
				}
				Section("Wiadomość głosowa") {
					if voiceRecorder.state == .recording {
						HStack {
							ProgressView()
							Text("Nagrywanie… \(formatTime(voiceRecorder.elapsedTime))")
						}
						.accessibilityElement(children: .combine)
						.accessibilityIdentifier("contact.voice.recordingStatus")

						Button("Zatrzymaj") {
							voiceRecorder.stopRecording()
							UIAccessibility.post(notification: .announcement, argument: "Nagrywanie zakończone")
						}
						.accessibilityIdentifier("contact.voice.stop")
						.accessibilityHint("Zatrzymuje nagrywanie.")
					}
					else if voiceRecorder.state == .recorded || voiceRecorder.state == .playingPreview {
						Text("Długość: \(formatTime(TimeInterval(voiceRecorder.recordedDurationMs) / 1000.0))")
							.accessibilityIdentifier("contact.voice.duration")

						Button(voiceRecorder.state == .playingPreview ? "Zatrzymaj odsłuch" : "Odsłuchaj") {
							voiceRecorder.togglePreview()
						}
						.accessibilityIdentifier("contact.voice.preview")
						.accessibilityHint("Odtwarza nagraną głosówkę.")

						Button("Usuń nagranie", role: .destructive) {
							voiceRecorder.reset()
							UIAccessibility.post(notification: .announcement, argument: "Nagranie usunięte")
						}
						.accessibilityIdentifier("contact.voice.delete")
						.accessibilityHint("Usuwa nagraną głosówkę.")

						Button {
							Task {
								guard let url = voiceRecorder.recordedFileURL else { return }
								let didSend = await viewModel.sendVoice(using: api, audioFileURL: url, durationMs: voiceRecorder.recordedDurationMs)
								guard didSend else { return }

								voiceRecorder.reset()
								UIAccessibility.post(notification: .announcement, argument: "Głosówka wysłana pomyślnie")
								dismiss()
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
						.disabled(!canSendVoice || viewModel.isSending)
						.accessibilityIdentifier("contact.voice.send")
						.accessibilityHint(canSendVoice ? "Wysyła głosówkę do redakcji." : "Wpisz imię i nagraj głosówkę, aby wysłać.")
					}
					else {
						Button("Nagraj") {
							Task {
								await voiceRecorder.startRecording(pausing: audioPlayer)
								if voiceRecorder.state == .recording {
									UIAccessibility.post(notification: .announcement, argument: "Rozpoczęto nagrywanie")
								}
							}
						}
						.accessibilityIdentifier("contact.voice.record")
						.accessibilityHint("Rozpoczyna nagrywanie wiadomości głosowej. Maksymalnie 20 minut.")
						.disabled(viewModel.isSending)
					}
				}
				Section {
					Button {
						Task {
							let didSend = await viewModel.send(using: api)
							guard didSend else { return }

							voiceRecorder.reset()
							UIAccessibility.post(notification: .announcement, argument: "Wiadomość wysłana pomyślnie")
							dismiss()
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
								Text("Wyślij wiadomość")
							}
						}
						.disabled(!canSend || viewModel.isSending)
						.accessibilityIdentifier("contact.send")
						.accessibilityHint(canSend ? "Wysyła wiadomość." : "Uzupełnij imię i wiadomość, aby wysłać.")
						.alert("Błąd", isPresented: $viewModel.shouldShowError) {
							Button("OK") {}
						} message: {
							Text(viewModel.errorMessage)
						}
					}
				}
			.navigationTitle("Kontakt")
			.toolbar {
				Button("Anuluj") {
					voiceRecorder.reset()
					dismiss()
				}
				.accessibilityIdentifier("contact.cancel")
				.accessibilityHint("Zamyka formularz bez wysyłania.")
			}
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
		.onChange(of: viewModel.shouldShowError) { shouldShowError in
			guard !shouldShowError else { return }
			focusedField = .message
		}
		.onDisappear {
			voiceRecorder.reset()
		}
	}

	private func formatTime(_ seconds: TimeInterval) -> String {
		guard seconds.isFinite, seconds > 0 else { return "00:00" }
		let total = Int(seconds.rounded(.down))
		let m = total / 60
		let s = total % 60
		return String(format: "%02d:%02d", m, s)
	}
}
