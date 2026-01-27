import Foundation

enum ContentKindLabelPosition: String, CaseIterable, Identifiable {
	case before
	case after

	var id: String { rawValue }

	var title: String {
		switch self {
		case .before:
			return "Przed"
		case .after:
			return "Po"
		}
	}
}

enum PlaybackRateRememberMode: String, CaseIterable, Identifiable {
	case global
	case perEpisode

	var id: String { rawValue }

	var title: String {
		switch self {
		case .global:
			return "Globalnie"
		case .perEpisode:
			return "Dla każdego odcinka"
		}
	}
}

@MainActor
final class SettingsStore: ObservableObject {
	private let userDefaults: UserDefaults
	private let contentKindLabelPositionKey: String
	private let playbackRateRememberModeKey: String

	@Published var contentKindLabelPosition: ContentKindLabelPosition = .before {
		didSet {
			userDefaults.set(contentKindLabelPosition.rawValue, forKey: contentKindLabelPositionKey)
		}
	}

	@Published var playbackRateRememberMode: PlaybackRateRememberMode = .global {
		didSet {
			userDefaults.set(playbackRateRememberMode.rawValue, forKey: playbackRateRememberModeKey)
		}
	}

	init(
		userDefaults: UserDefaults = .standard,
		contentKindLabelPositionKey: String = "settings.contentKindLabelPosition",
		playbackRateRememberModeKey: String = "settings.playbackRateRememberMode"
	) {
		self.userDefaults = userDefaults
		self.contentKindLabelPositionKey = contentKindLabelPositionKey
		self.playbackRateRememberModeKey = playbackRateRememberModeKey

		if let rawValue = userDefaults.string(forKey: contentKindLabelPositionKey),
		   let loaded = ContentKindLabelPosition(rawValue: rawValue) {
			contentKindLabelPosition = loaded
		}

		if let rawValue = userDefaults.string(forKey: playbackRateRememberModeKey),
		   let loaded = PlaybackRateRememberMode(rawValue: rawValue) {
			playbackRateRememberMode = loaded
		}
	}
}
