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
}

struct ContactView: View {
	@EnvironmentObject var api: TyfloAPI
	@Environment(\.dismiss) var dismiss
	@StateObject private var viewModel = ContactViewModel()
	@AccessibilityFocusState private var focusedField: Field?

	private enum Field: Hashable {
		case name
		case message
	}

	var body: some View {
		let canSend = viewModel.canSend
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
				Section {
					Button {
						Task {
							let didSend = await viewModel.send(using: api)
							guard didSend else { return }

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
							Text("Wyślij")
						}
					}
					.accessibilityIdentifier("contact.send")
					.accessibilityHint(canSend ? "Wysyła wiadomość." : "Uzupełnij imię i wiadomość, aby wysłać.")
					.alert("Błąd", isPresented: $viewModel.shouldShowError) {
						Button("OK") {}
					} message: {
						Text(viewModel.errorMessage)
					}
				}
				.disabled(!canSend || viewModel.isSending)
			}
			.navigationTitle("Kontakt")
			.toolbar {
				Button("Anuluj") {
					dismiss()
				}
				.accessibilityIdentifier("contact.cancel")
				.accessibilityHint("Zamyka formularz bez wysyłania.")
			}
		}
		.task {
			focusedField = .name
		}
		.onChange(of: viewModel.shouldShowError) { shouldShowError in
			guard !shouldShowError else { return }
			focusedField = .message
		}
	}
}
