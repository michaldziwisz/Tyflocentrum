import XCTest

final class TyflocentrumSmokeTests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	func testAppLaunchesAndShowsTabs() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING"]
		app.launch()

		XCTAssertTrue(app.tabBars.buttons["Nowości"].waitForExistence(timeout: 5))
		XCTAssertTrue(app.tabBars.buttons["Podcasty"].exists)
		XCTAssertTrue(app.tabBars.buttons["Artykuły"].exists)
		XCTAssertTrue(app.tabBars.buttons["Szukaj"].exists)
		XCTAssertTrue(app.tabBars.buttons["Więcej"].exists)
	}

	func testCanOpenRadioPlayerFromMoreTab() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING"]
		app.launch()

		app.tabBars.buttons["Więcej"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: 5))
		radioButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: 5))

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.exists)
	}

	func testCanOpenPodcastPlayerAndSeeSeekControls() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING"]
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: 5))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: 5))

		let listenButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.listen").firstMatch
		XCTAssertTrue(listenButton.waitForExistence(timeout: 5))
		listenButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: 5))

		let skipBack = app.descendants(matching: .any).matching(identifier: "player.skipBackward30").firstMatch
		XCTAssertTrue(skipBack.exists)

		let skipForward = app.descendants(matching: .any).matching(identifier: "player.skipForward30").firstMatch
		XCTAssertTrue(skipForward.exists)

		let speedButton = app.descendants(matching: .any).matching(identifier: "player.speed").firstMatch
		XCTAssertTrue(speedButton.exists)
	}
}
