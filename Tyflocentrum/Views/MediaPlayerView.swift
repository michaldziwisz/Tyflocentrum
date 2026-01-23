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
		audioPlayer.togglePlayPause(url: podcast)
	}
	var body: some View {
		let isPlayingCurrentItem = audioPlayer.isPlaying && audioPlayer.currentURL == podcast
		HStack(alignment: .center, spacing: 20) {
			Spacer()
			Button {
				togglePlayback()
			} label: {
				Image(systemName: isPlayingCurrentItem ? "pause.circle.fill" : "play.circle.fill")
					.font(.title)
					.imageScale(.large)
			}
			.accessibilityLabel(isPlayingCurrentItem ? "Pauza" : "Odtwarzaj")
			.accessibilityValue(isPlayingCurrentItem ? "Odtwarzanie trwa" : "Odtwarzanie wstrzymane")
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
		}.navigationTitle("Odtwarzacz").onAppear {
			audioPlayer.play(url: podcast)
		}.accessibilityAction(.magicTap) {
			togglePlayback()
		}
	}
}
