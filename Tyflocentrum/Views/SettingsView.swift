import SwiftUI

struct SettingsView: View {
	@EnvironmentObject private var settings: SettingsStore

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
		}
		.navigationTitle("Ustawienia")
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityIdentifier("settings.view")
	}
}

