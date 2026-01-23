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
		NavigationView {
			Form {
				Section {
					TextField("Imię", text: $name)
						.textContentType(.name)
						.accessibilityIdentifier("contact.name")
					TextEditor(text: $message)
						.accessibilityLabel("Wiadomość")
						.accessibilityIdentifier("contact.message")
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
					.alert("Błąd", isPresented: $shouldShowError) {
						Button("OK") {}
					} message: {
						Text(errorMessage)
					}
				}.disabled(name.isEmpty || message.isEmpty)
			}.toolbar {
				Button("Anuluj") {
					dismiss()
				}
				.accessibilityIdentifier("contact.cancel")
			}
		}
	}
}
