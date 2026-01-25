//
//  LibraryView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/10/2022.
//

import Foundation
import SwiftUI

struct MoreView: View {
	@EnvironmentObject var api: TyfloAPI
	@State private var shouldShowContactForm = false
	@State private var shouldShowNoLiveAlert = false

	private func performLiveCheck() async {
		let (available, _) = await api.isTPAvailable()
		if available {
			shouldShowContactForm = true
		}
		else {
			shouldShowNoLiveAlert = true
		}
	}

	var body: some View {
		NavigationView {
			List {
				Section {
					NavigationLink {
						MediaPlayerView(
							podcast: URL(string: "https://radio.tyflopodcast.net/hls/stream.m3u8")!,
							title: "Tyfloradio",
							subtitle: nil,
							canBeLive: true
						)
					} label: {
						Text("Posłuchaj Tyfloradia")
					}
					.accessibilityRemoveTraits(.isButton)
					.accessibilityHint("Otwiera odtwarzacz strumienia na żywo.")
					.accessibilityIdentifier("more.tyfloradio")
				}

				Section {
					Button("Skontaktuj się z radiem") {
						Task {
							await performLiveCheck()
						}
					}
					.accessibilityHint("Sprawdza, czy trwa audycja interaktywna i otwiera formularz kontaktu.")
					.accessibilityIdentifier("more.contactRadio")
				}
			}
			.navigationTitle("Więcej")
			.alert("Błąd", isPresented: $shouldShowNoLiveAlert) {
				Button("OK") {}
			} message: {
				Text("Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna.")
			}
			.sheet(isPresented: $shouldShowContactForm) {
				ContactView()
			}
		}
	}
}
