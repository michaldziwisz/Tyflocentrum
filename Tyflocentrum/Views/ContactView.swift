//
//  ContactView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 23/11/2022.
//

import Foundation
import SwiftUI
struct ContactView: View {
	@EnvironmentObject var api: TyfloAPI
	@Environment(\.dismiss) var dismiss
	@AppStorage("name") private var name = ""
	@AppStorage("CurrentMSG") private var message = "\nWysłane przy pomocy aplikacji Tyflocentrum"
	@State private var shouldShowError = false
	@State private var errorMessage = ""
	@MainActor
	func performSend() async -> Bool {
		let (success, error) = await api.contactRadio(as: name, with: message)
		guard success else {
			errorMessage = error ?? "Nieznany błąd"
			shouldShowError = true
			return false
		}
		return true
	}
	var body: some View {
		let canSend = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		NavigationView {
			Form {
				Section {
					TextField("Imię", text: $name)
						.textContentType(.name)
						.accessibilityIdentifier("contact.name")
						.accessibilityHint("Wpisz imię, które będzie widoczne przy wiadomości.")
					TextEditor(text: $message)
						.accessibilityLabel("Wiadomość")
						.accessibilityIdentifier("contact.message")
						.accessibilityHint("Wpisz treść wiadomości do redakcji.")
				}
				Section {
					Button("Wyślij") {
						Task {
							let didSend = await performSend()
							guard didSend else { return }

							message = "\nWysłane przy pomocy aplikacji Tyflocentrum"
							UIAccessibility.post(notification: .announcement, argument: "Wiadomość wysłana pomyślnie")
							dismiss()
						}
					}
					.accessibilityIdentifier("contact.send")
					.accessibilityHint(canSend ? "Wysyła wiadomość." : "Uzupełnij imię i wiadomość, aby wysłać.")
					.alert("Błąd", isPresented: $shouldShowError) {
						Button("OK") {}
					} message: {
						Text(errorMessage)
					}
				}.disabled(!canSend)
			}.toolbar {
				Button("Anuluj") {
					dismiss()
				}
				.accessibilityIdentifier("contact.cancel")
			}
		}
	}
}
