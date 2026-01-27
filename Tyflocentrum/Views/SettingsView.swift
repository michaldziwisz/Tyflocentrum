import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var settings: SettingsStore
	@EnvironmentObject private var audioPlayer: AudioPlayer

	var body: some View {
		List {
			Section("Wskazuj typ treści") {
				Picker("Pozycja", selection: $settings.contentKindLabelPosition) {
					ForEach(ContentKindLabelPosition.allCases) { position in
						Text(position.title)
							.tag(position)
					}
				}
				.pickerStyle(.segmented)
				.accessibilityLabel("Wskazuj typ treści")
				.accessibilityValue(settings.contentKindLabelPosition.title)
				.accessibilityHint("Określa, czy typ treści będzie czytany przed czy po tytule na listach.")
				.accessibilityIdentifier("settings.contentKindLabelPosition")
			}

			Section("Zapamiętaj prędkość przyspieszania") {
				Picker("Tryb", selection: $settings.playbackRateRememberMode) {
					ForEach(PlaybackRateRememberMode.allCases) { mode in
						Text(mode.title)
							.tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.accessibilityLabel("Zapamiętaj prędkość przyspieszania")
				.accessibilityValue(settings.playbackRateRememberMode.title)
				.accessibilityHint("Określa, czy prędkość odtwarzania ma być wspólna, czy zapamiętywana osobno dla każdego odcinka.")
				.accessibilityIdentifier("settings.playbackRateRememberMode")
			}
		}
		.onChange(of: settings.playbackRateRememberMode) { _ in
			audioPlayer.applyPlaybackRateRememberModeChange()
		}
		.navigationTitle("Ustawienia")
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityIdentifier("settings.view")
	}
}
