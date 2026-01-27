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

@MainActor
final class SettingsStore: ObservableObject {
	private let userDefaults: UserDefaults
	private let contentKindLabelPositionKey: String

	@Published var contentKindLabelPosition: ContentKindLabelPosition = .before {
		didSet {
			userDefaults.set(contentKindLabelPosition.rawValue, forKey: contentKindLabelPositionKey)
		}
	}

	init(
		userDefaults: UserDefaults = .standard,
		contentKindLabelPositionKey: String = "settings.contentKindLabelPosition"
	) {
		self.userDefaults = userDefaults
		self.contentKindLabelPositionKey = contentKindLabelPositionKey

		if let rawValue = userDefaults.string(forKey: contentKindLabelPositionKey),
		   let loaded = ContentKindLabelPosition(rawValue: rawValue) {
			contentKindLabelPosition = loaded
		}
	}
}

