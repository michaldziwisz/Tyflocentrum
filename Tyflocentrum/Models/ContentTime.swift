import Foundation

struct ContentTimeLabel: Equatable {
	let visible: String
	let accessible: String
	static let unavailable = ContentTimeLabel(visible: "Czas niedostępny", accessible: "Czas niedostępny")

	static func reading(_ minutes: Int) -> Self {
		Self(visible: "Czytanie: około \(minutes) min", accessible: "Czytanie: około \(minutes) \(minutes == 1 ? "minuty" : "minut")")
	}

	static func audio(_ seconds: Int) -> Self {
		let values = [seconds / 3600, seconds % 3600 / 60, seconds % 60]
		let short = ["godz.", "min", "s"]
		let forms = [["godzina", "godziny", "godzin"], ["minuta", "minuty", "minut"], ["sekunda", "sekundy", "sekund"]]
		var visible: [String] = []
		var accessible: [String] = []
		for index in values.indices where values[index] > 0 {
			let value = values[index]
			let form = value == 1 ? 0 : ((2 ... 4).contains(value % 10) && !(12 ... 14).contains(value % 100) ? 1 : 2)
			visible.append("\(value) \(short[index])")
			accessible.append("\(value) \(forms[index][form])")
		}
		return Self(visible: "Czas trwania: " + visible.joined(separator: " "), accessible: "Czas trwania: " + accessible.joined(separator: " "))
	}
}

/// Dekoder opcjonalnego rozszerzenia nigdy nie odrzuca poprawnego wpisu WP.
/// Każde pole jest niezależne: błąd tekstu nie odbiera poprawnego audio.
struct ContentTimeMetadata: Codable, Hashable {
	var schemaVersion: Int?
	var durationSeconds: Double?
	var wordCount: Int?
	var readingMinutes: Int?
	var textStatus: String?
	var audioStatus: String?

	enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case durationSeconds = "duration_seconds"
		case wordCount = "word_count"
		case readingMinutes = "reading_minutes"
		case textStatus = "text_status"
		case audioStatus = "audio_status"
	}

	init(from decoder: Decoder) throws {
		let c = try? decoder.container(keyedBy: CodingKeys.self)
		schemaVersion = try? c?.decode(Int.self, forKey: .schemaVersion)
		durationSeconds = try? c?.decode(Double.self, forKey: .durationSeconds)
		wordCount = try? c?.decode(Int.self, forKey: .wordCount)
		readingMinutes = try? c?.decode(Int.self, forKey: .readingMinutes)
		textStatus = try? c?.decode(String.self, forKey: .textStatus)
		audioStatus = try? c?.decode(String.self, forKey: .audioStatus)
	}

	var audioSeconds: Int? {
		guard schemaVersion == 1, audioStatus == "ready", let seconds = durationSeconds,
		      seconds.isFinite, seconds > 0, seconds <= 2_147_483_647 else { return nil }
		return Int(ceil(seconds))
	}

	var audioTime: ContentTimeLabel { audioSeconds.map(ContentTimeLabel.audio) ?? .unavailable }

	var validReadingMinutes: Int? {
		guard schemaVersion == 1, textStatus == "ready", let words = wordCount, words > 0,
		      let minutes = readingMinutes, minutes > 0,
		      minutes == words / 200 + (words % 200 == 0 ? 0 : 1) else { return nil }
		return minutes
	}
}

struct ContentTimeRecord: Codable, Hashable {
	var id: Int?
	var tyflocentrum: ContentTimeMetadata?
	var freshness: String?
	var checkedAt: String?
	var modifiedGMT: String?

	enum CodingKeys: String, CodingKey {
		case id, tyflocentrum, freshness
		case checkedAt = "checked_at"
		case modifiedGMT = "modified_gmt"
	}

	init(from decoder: Decoder) throws {
		let c = try? decoder.container(keyedBy: CodingKeys.self)
		id = try? c?.decode(Int.self, forKey: .id)
		tyflocentrum = try? c?.decode(ContentTimeMetadata.self, forKey: .tyflocentrum)
		freshness = try? c?.decode(String.self, forKey: .freshness)
		checkedAt = try? c?.decode(String.self, forKey: .checkedAt)
		modifiedGMT = try? c?.decode(String.self, forKey: .modifiedGMT)
	}

	private static let dateLock = NSLock()
	private static let fractionalDateParser: ISO8601DateFormatter = {
		let parser = ISO8601DateFormatter()
		parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return parser
	}()

	private static let dateParser = ISO8601DateFormatter()

	static func date(_ value: String?) -> Date? {
		guard var value else { return nil }
		if value.count == 19 { value += "Z" }
		dateLock.lock()
		defer { dateLock.unlock() }
		return fractionalDateParser.date(from: value) ?? dateParser.date(from: value)
	}

	var expiresAt: Date? { Self.date(checkedAt)?.addingTimeInterval(86400) }

	func readingTime(now: Date, sourceModified: String?) -> ContentTimeLabel {
		guard freshness == "fresh", let checked = Self.date(checkedAt),
		      checked <= now, now.timeIntervalSince(checked) <= 86400,
		      let minutes = tyflocentrum?.validReadingMinutes else { return .unavailable }
		if let source = Self.date(sourceModified) {
			guard let metadata = Self.date(modifiedGMT), source <= metadata else { return .unavailable }
		}
		return .reading(minutes)
	}
}

struct ContentTimeKey: Hashable, Codable {
	enum Kind: String, CaseIterable, Codable { case posts, pages, podcast }
	let kind: Kind
	let id: Int
	var source: String { kind == .podcast ? "tyflopodcast.net" : "tyfloswiat.pl" }
	var isValid: Bool { id > 0 && id <= 2_147_483_647 }
}
