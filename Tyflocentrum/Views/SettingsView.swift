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

			Section("Powiadomienia push") {
				Toggle(
					"Wszystkie",
					isOn: Binding(
						get: { settings.pushNotificationPreferences.allEnabled },
						set: { enabled in
							var next = settings.pushNotificationPreferences
							next.setAll(enabled)
							settings.pushNotificationPreferences = next
						}
					)
				)
				.accessibilityHint("Włącza lub wyłącza wszystkie powiadomienia naraz.")
				.accessibilityIdentifier("settings.push.all")

				Toggle("Nowe odcinki Tyflopodcast", isOn: $settings.pushNotificationPreferences.podcast)
					.accessibilityHint("Powiadamia o nowych odcinkach w serwisie Tyflopodcast.")
					.accessibilityIdentifier("settings.push.podcast")

				Toggle("Nowe artykuły Tyfloświat", isOn: $settings.pushNotificationPreferences.article)
					.accessibilityHint("Powiadamia o nowych artykułach w serwisie Tyfloświat.")
					.accessibilityIdentifier("settings.push.article")

				Toggle("Start audycji interaktywnej Tyfloradio", isOn: $settings.pushNotificationPreferences.live)
					.accessibilityHint("Powiadamia o uruchomieniu audycji interaktywnej na żywo w Tyfloradiu.")
					.accessibilityIdentifier("settings.push.live")

				Toggle("Zmiana ramówki Tyfloradio", isOn: $settings.pushNotificationPreferences.schedule)
					.accessibilityHint("Powiadamia o zmianach w ramówce Tyfloradia.")
					.accessibilityIdentifier("settings.push.schedule")
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
