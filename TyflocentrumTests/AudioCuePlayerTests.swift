import AVFoundation
import XCTest

@testable import Tyflocentrum

final class AudioCuePlayerTests: XCTestCase {
	func testSessionOptionsRouteToSpeakerIncludesDefaultToSpeaker() {
		let options = AudioCuePlayer.sessionOptions(routeToSpeaker: true)
		XCTAssertTrue(options.contains(.defaultToSpeaker))
	}

	func testSessionOptionsRouteToSpeakerDoesNotIncludeDefaultToSpeakerWhenFalse() {
		let options = AudioCuePlayer.sessionOptions(routeToSpeaker: false)
		XCTAssertFalse(options.contains(.defaultToSpeaker))
	}
}

