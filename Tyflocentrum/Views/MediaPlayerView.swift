//
//  MediaPlayerView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 19/11/2022.
//

import Foundation
import SwiftUI
struct MediaPlayerView: View {
	private static let timeFormatterHMS: DateComponentsFormatter = {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.hour, .minute, .second]
		formatter.unitsStyle = .positional
		formatter.zeroFormattingBehavior = [.pad]
		return formatter
	}()

	private static let timeFormatterMS: DateComponentsFormatter = {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.minute, .second]
		formatter.unitsStyle = .positional
		formatter.zeroFormattingBehavior = [.pad]
		return formatter
	}()

	@EnvironmentObject var api: TyfloAPI
	@EnvironmentObject var audioPlayer: AudioPlayer
	let podcast: URL
	let title: String
	let subtitle: String?
	let canBeLive: Bool
	@State private var shouldShowContactForm = false
	@State private var shouldShowNoLiveAlert = false
	@State private var isScrubbing = false
	@State private var scrubPosition: Double = 0
	func performLiveCheck() async -> Void {
		let (available, _) = await api.isTPAvailable()
		if available {
			shouldShowContactForm = true
		}
		else {
			shouldShowNoLiveAlert = true
		}
	}
	private func announceIfVoiceOver(_ message: String) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		UIAccessibility.post(notification: .announcement, argument: message)
	}

	private func announcePlaybackRate() {
		let newPlaybackRateText = String(format: "%.2g", audioPlayer.playbackRate)
		announceIfVoiceOver("Prędkość \(newPlaybackRateText)x")
	}

	private func announceSeek(delta: Double) {
		let seconds = Int(abs(delta))
		let fallback = delta < 0 ? "Cofnięto \(seconds) sekund." : "Przewinięto do przodu \(seconds) sekund."

		guard let duration = audioPlayer.duration, duration.isFinite, duration > 0 else {
			announceIfVoiceOver(fallback)
			return
		}

		let target = SeekPolicy.targetTime(elapsed: audioPlayer.elapsedTime, delta: delta) ?? audioPlayer.elapsedTime
		let positionText = formatTime(target)
		let durationText = formatTime(duration)
		announceIfVoiceOver("Pozycja \(positionText) z \(durationText).")
	}

	func togglePlayback() {
		let willPlay = audioPlayer.currentURL != podcast || !audioPlayer.isPlaying
		audioPlayer.togglePlayPause(url: podcast, title: title, subtitle: subtitle, isLiveStream: canBeLive)
		announceIfVoiceOver(willPlay ? "Odtwarzanie." : "Pauza.")
	}
	func formatTime(_ seconds: TimeInterval) -> String {
		guard seconds.isFinite, seconds >= 0 else { return "--:--" }
		let formatter = seconds >= 3600 ? Self.timeFormatterHMS : Self.timeFormatterMS
		return formatter.string(from: seconds) ?? "--:--"
	}
	var body: some View {
		let isLiveStream = canBeLive
		let isPlayingCurrentItem = audioPlayer.isPlaying && audioPlayer.currentURL == podcast
		let displayedTime = isScrubbing ? scrubPosition : audioPlayer.elapsedTime
		let playbackRateText = String(format: "%.2g", audioPlayer.playbackRate)
		VStack(spacing: 24) {
			VStack(spacing: 6) {
				Text(title)
					.font(.headline)
					.multilineTextAlignment(.center)

				if let subtitle, !subtitle.isEmpty {
					Text(subtitle)
						.font(.subheadline)
						.foregroundColor(.secondary)
						.multilineTextAlignment(.center)
				}
			}
			.accessibilityElement(children: .combine)
			.accessibilityAddTraits(.isHeader)

			HStack(alignment: .center, spacing: 24) {
				if !isLiveStream {
					Button {
						audioPlayer.skipBackward(seconds: 30)
						announceSeek(delta: -30)
					} label: {
						Image(systemName: "gobackward.30")
							.font(.title2)
							.imageScale(.large)
					}
					.accessibilityLabel("Cofnij 30 sekund")
					.accessibilityHint("Dwukrotnie stuknij, aby cofnąć o 30 sekund.")
					.accessibilityIdentifier("player.skipBackward30")
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
				.accessibilityHint(isPlayingCurrentItem ? "Dwukrotnie stuknij, aby wstrzymać odtwarzanie." : "Dwukrotnie stuknij, aby rozpocząć odtwarzanie.")
				.accessibilityIdentifier("player.playPause")

				if !isLiveStream {
					Button {
						audioPlayer.skipForward(seconds: 30)
						announceSeek(delta: 30)
					} label: {
						Image(systemName: "goforward.30")
							.font(.title2)
							.imageScale(.large)
					}
					.accessibilityLabel("Przewiń do przodu 30 sekund")
					.accessibilityHint("Dwukrotnie stuknij, aby przewinąć do przodu o 30 sekund.")
					.accessibilityIdentifier("player.skipForward30")
				}
			}

			if !isLiveStream {
				VStack(spacing: 12) {
					if let duration = audioPlayer.duration, duration.isFinite, duration > 0 {
						HStack {
							Text(formatTime(displayedTime))
								.monospacedDigit()
								.foregroundColor(.secondary)
							Spacer()
							Text(formatTime(duration))
								.monospacedDigit()
								.foregroundColor(.secondary)
						}
						.accessibilityHidden(true)

						Slider(
							value: Binding(
								get: { displayedTime },
								set: { newValue in
									scrubPosition = newValue
								}
							),
							in: 0...duration,
							onEditingChanged: { editing in
								isScrubbing = editing
								if editing {
									scrubPosition = audioPlayer.elapsedTime
								} else {
									audioPlayer.seek(to: scrubPosition)
								}
							}
						)
						.accessibilityLabel("Pozycja odtwarzania")
						.accessibilityValue("\(formatTime(displayedTime)) z \(formatTime(duration))")
						.accessibilityHint("Przesuń w górę lub w dół jednym palcem, aby przewinąć.")
						.accessibilityIdentifier("player.position")
					}
					else {
						ProgressView()
							.accessibilityLabel("Ładowanie czasu trwania")
					}
				}
			}

			if !isLiveStream {
				Button {
					audioPlayer.cyclePlaybackRate()
					announcePlaybackRate()
				} label: {
					Text("Prędkość: \(audioPlayer.playbackRate, specifier: "%.2gx")")
				}
				.accessibilityLabel("Zmień prędkość odtwarzania")
				.accessibilityValue("\(playbackRateText)x")
				.accessibilityHint("Dwukrotnie stuknij, aby przełączyć prędkość. Przesuń w górę lub w dół, aby zwiększyć lub zmniejszyć.")
				.accessibilityIdentifier("player.speed")
				.accessibilityAdjustableAction { direction in
					switch direction {
					case .increment:
						audioPlayer.cyclePlaybackRate()
					case .decrement:
						audioPlayer.setPlaybackRate(PlaybackRatePolicy.previous(before: audioPlayer.playbackRate))
					@unknown default:
						break
					}
					announcePlaybackRate()
				}
			}

			if canBeLive {
				Button("Skontaktuj się z radiem") {
					Task {
						await performLiveCheck()
					}
				}
				.accessibilityHint("Sprawdza, czy trwa audycja interaktywna i otwiera formularz kontaktu.")
				.accessibilityIdentifier("player.contactRadio")
				.alert("Błąd", isPresented: $shouldShowNoLiveAlert) {
					Button("OK") {}
				} message: {
					Text("Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna.")
				}
				.sheet(isPresented: $shouldShowContactForm) {
					ContactView()
				}
			}

			Spacer()
		}
		.padding()
		.navigationTitle("Odtwarzacz")
		.onAppear {
			guard !ProcessInfo.processInfo.arguments.contains("UI_TESTING") else { return }
			audioPlayer.play(url: podcast, title: title, subtitle: subtitle, isLiveStream: canBeLive)
		}
		.accessibilityAction(.magicTap) {
			togglePlayback()
		}
	}
}
