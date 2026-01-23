import XCTest

final class TyflocentrumSmokeTests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	private func makeApp() -> XCUIApplication {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING"]
		return app
	}

	func testAppLaunchesAndShowsTabs() {
		let app = makeApp()
		app.launch()

		XCTAssertTrue(app.tabBars.buttons["Nowości"].waitForExistence(timeout: 5))
		XCTAssertTrue(app.tabBars.buttons["Podcasty"].exists)
		XCTAssertTrue(app.tabBars.buttons["Artykuły"].exists)
		XCTAssertTrue(app.tabBars.buttons["Szukaj"].exists)
		XCTAssertTrue(app.tabBars.buttons["Więcej"].exists)
	}

	func testCanOpenRadioPlayerFromMoreTab() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Więcej"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: 5))
		radioButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: 5))
		XCTAssertEqual(playPauseButton.label, "Odtwarzaj")

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.exists)
		XCTAssertEqual(contactButton.label, "Skontaktuj się z radiem")
	}

	func testCanOpenPodcastPlayerAndSeeSeekControls() {
		let app = makeApp()
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
		XCTAssertTrue(["Odtwarzaj", "Pauza"].contains(playPauseButton.label))

		let skipBack = app.descendants(matching: .any).matching(identifier: "player.skipBackward30").firstMatch
		XCTAssertTrue(skipBack.exists)
		XCTAssertEqual(skipBack.label, "Cofnij 30 sekund")

		let skipForward = app.descendants(matching: .any).matching(identifier: "player.skipForward30").firstMatch
		XCTAssertTrue(skipForward.exists)
		XCTAssertEqual(skipForward.label, "Przewiń do przodu 30 sekund")

		let speedButton = app.descendants(matching: .any).matching(identifier: "player.speed").firstMatch
		XCTAssertTrue(speedButton.exists)
		XCTAssertEqual(speedButton.label, "Zmień prędkość odtwarzania")
	}

	func testCanSearchAndOpenPodcastFromResults() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Szukaj"].tap()

		let searchField = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
		XCTAssertTrue(searchField.waitForExistence(timeout: 5))
		searchField.tap()
		searchField.typeText("test")

		let searchButton = app.descendants(matching: .any).matching(identifier: "search.button").firstMatch
		XCTAssertTrue(searchButton.exists)
		searchButton.tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: 5))
		XCTAssertEqual(podcastRow.label, "Test podcast")
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: 5))
	}

	func testRadioContactShowsNoLiveAlert() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Więcej"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: 5))
		radioButton.tap()

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.waitForExistence(timeout: 5))
		contactButton.tap()

		let alert = app.alerts["Błąd"]
		XCTAssertTrue(alert.waitForExistence(timeout: 5))
		XCTAssertTrue(alert.staticTexts["Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna."].exists)
	}
}
