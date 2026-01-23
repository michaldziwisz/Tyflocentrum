//
//  MediaPlayerView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/11/2022.
//

import Foundation
import SwiftUI
struct MediaPlayerView: View {
	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject var audioPlayer: AudioPlayer
	let podcast: URL
	let title: String
	let subtitle: String?
	let canBeLive: Bool
	@State private var shouldShowContactForm = false
	@State private var shouldShowNoLiveAlert = false
	func performLiveCheck() async -> Void{
		let (available, _) = await api.isTPAvailable()
		if available {
			shouldShowContactForm = true
		}
		else {
			shouldShowNoLiveAlert = true
		}
	}
	func togglePlayback() {
		audioPlayer.togglePlayPause(url: podcast, title: title, subtitle: subtitle, isLiveStream: canBeLive)
	}
	var body: some View {
		let isLiveStream = canBeLive
		let isPlayingCurrentItem = audioPlayer.isPlaying && audioPlayer.currentURL == podcast
		VStack(spacing: 24) {
			VStack(spacing: 6) {
				Text(title)
					.font(.headline)
					.multilineTextAlignment(.center)
					.accessibilityAddTraits(.isHeader)

				if let subtitle, !subtitle.isEmpty {
					Text(subtitle)
						.font(.subheadline)
						.foregroundColor(.secondary)
						.multilineTextAlignment(.center)
				}
			}

			HStack(alignment: .center, spacing: 24) {
				if !isLiveStream {
					Button {
						audioPlayer.skipBackward(seconds: 30)
					} label: {
						Image(systemName: "gobackward.30")
							.font(.title2)
							.imageScale(.large)
					}
					.accessibilityLabel("Cofnij 30 sekund")
				}

				Button {
					togglePlayback()
				} label: {
					Image(systemName: isPlayingCurrentItem ? "pause.circle.fill" : "play.circle.fill")
						.font(.largeTitle)
						.imageScale(.large)
				}
				.accessibilityLabel(isPlayingCurrentItem ? "Pauza" : "Odtwarzaj")
				.accessibilityValue(isPlayingCurrentItem ? "Odtwarzanie trwa" : "Odtwarzanie wstrzymane")

				if !isLiveStream {
					Button {
						audioPlayer.skipForward(seconds: 30)
					} label: {
						Image(systemName: "goforward.30")
							.font(.title2)
							.imageScale(.large)
					}
					.accessibilityLabel("Przewiń do przodu 30 sekund")
				}
			}

			if !isLiveStream {
				Button {
					audioPlayer.cyclePlaybackRate()
				} label: {
					Text("Prędkość: \(audioPlayer.playbackRate, specifier: "%.2gx")")
				}
				.accessibilityLabel("Zmień prędkość odtwarzania")
				.accessibilityValue("\(audioPlayer.playbackRate, specifier: "%.2g") razy")
			}

			if canBeLive {
				Button("Skontaktuj się z radiem") {
					Task {
						await performLiveCheck()
					}
				}.alert("Błąd", isPresented: $shouldShowNoLiveAlert) {
					Button("OK"){}
				} message: {
					Text("Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna.")
				}.sheet(isPresented: $shouldShowContactForm) {
					ContactView()
				}
			}
			Spacer()
		}
		.padding()
		.navigationTitle("Odtwarzacz")
		.onAppear {
			audioPlayer.play(url: podcast, title: title, subtitle: subtitle, isLiveStream: canBeLive)
		}.accessibilityAction(.magicTap) {
			togglePlayback()
		}
	}
}
