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
	@EnvironmentObject var audioPlayer: AudioPlayer
	@EnvironmentObject var magicTapCoordinator: MagicTapCoordinator
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
			VStack(spacing: 16) {
				Spacer()

				NavigationLink {
					MediaPlayerView(
						podcast: URL(string: "https://radio.tyflopodcast.net/hls/stream.m3u8")!,
						title: "Tyfloradio",
						subtitle: nil,
						canBeLive: true
					)
				} label: {
					Label("Posłuchaj Tyfloradia", systemImage: "dot.radiowaves.left.and.right")
						.frame(maxWidth: .infinity, minHeight: 56)
				}
				.buttonStyle(.borderedProminent)
				.accessibilityHint("Otwiera odtwarzacz strumienia na żywo.")
				.accessibilityIdentifier("more.tyfloradio")

				Button {
					Task {
						await performLiveCheck()
					}
				} label: {
					Label("Skontaktuj się z Tyfloradiem", systemImage: "envelope")
						.frame(maxWidth: .infinity, minHeight: 56)
				}
				.buttonStyle(.bordered)
				.accessibilityHint("Sprawdza, czy trwa audycja interaktywna i otwiera formularz kontaktu.")
				.accessibilityIdentifier("more.contactRadio")
			}
			.padding()
			.withAppMenu()
			.navigationTitle("Tyfloradio")
			.alert("Błąd", isPresented: $shouldShowNoLiveAlert) {
				Button("OK") {}
			} message: {
				Text("Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna.")
			}
				.sheet(isPresented: $shouldShowContactForm) {
					MagicTapHostingView(
						rootView: ContactView()
							.environmentObject(api)
							.environmentObject(audioPlayer)
							.environmentObject(magicTapCoordinator),
						onMagicTap: {
							magicTapCoordinator.perform {
								audioPlayer.toggleCurrentPlayback()
							}
						}
					)
				}
			}
		}
	}
