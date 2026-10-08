import Foundation
import XCTest
#if canImport(Tyflocentrum)
	@testable import Tyflocentrum
#endif

final class ContentTimeTests: XCTestCase {
	func testFractionalAudioAndPolishGrammar() throws {
		let data = Data(#"{"schema_version":1,"audio_status":"ready","duration_seconds":4983.1}"#.utf8)
		let metadata = try JSONDecoder().decode(ContentTimeMetadata.self, from: data)
		XCTAssertEqual(metadata.audioTime.visible, "Czas trwania: 1 godz. 23 min 4 s")
		XCTAssertEqual(metadata.audioTime.accessible, "Czas trwania: 1 godzina 23 minuty 4 sekundy")
	}

	func testMalformedOptionalMetadataIsLossy() throws {
		for raw in ["null", "true", "[]", "42", #"{"schema_version":true,"duration_seconds":true}"#] {
			let metadata = try JSONDecoder().decode(ContentTimeMetadata.self, from: Data(raw.utf8))
			XCTAssertEqual(metadata.audioTime, .unavailable)
		}
	}

	func testReadingExpiresInMemoryAndRejectsNewerSource() throws {
		let raw = #"{"id":1,"tyflocentrum":{"schema_version":1,"text_status":"ready","word_count":201,"reading_minutes":2},"freshness":"fresh","checked_at":"2026-10-08T11:00:00Z","modified_gmt":"2026-10-07T10:00:00"}"#
		let item = try JSONDecoder().decode(ContentTimeRecord.self, from: Data(raw.utf8))
		let now = try XCTUnwrap(ContentTimeRecord.date("2026-10-08T12:00:00Z"))
		XCTAssertEqual(item.readingTime(now: now, sourceModified: nil).accessible, "Czytanie: około 2 minut")
		XCTAssertEqual(item.readingTime(now: now.addingTimeInterval(86400), sourceModified: nil), .unavailable)
		XCTAssertEqual(item.readingTime(now: now, sourceModified: "2026-10-08T10:00:00"), .unavailable)
	}
}
