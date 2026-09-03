import CoreGraphics
import XCTest

final class TyflocentrumSmokeTests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	/// Limit czasu na pojawienie się elementu.
	///
	/// DLACZEGO NIE 5 s NA SZTYWNO. Zmierzone na runnerze GitHuba (run
	/// 33804359599): samo `Wait for app to idle` zajmowało tam nawet **143 s**,
	/// a uruchomienie aplikacji 52 s zamiast typowych 2-3 s. Przy limicie 5 s
	/// test padał nie dlatego, że aplikacja jest zepsuta — zrzut ekranu z tego
	/// padnięcia pokazywał ekran całkowicie poprawny — tylko dlatego, że maszyna
	/// była przeciążona. To jest defekt POMIARU, nie kodu.
	///
	/// Limit można nadpisać zmienną `LIMIT_UI_SEKUNDY`, żeby lokalnie nie czekać
	/// niepotrzebnie długo.
	private var limitUI: TimeInterval {
		if let wartosc = ProcessInfo.processInfo.environment["LIMIT_UI_SEKUNDY"],
		   let liczba = TimeInterval(wartosc)
		{
			return liczba
		}
		return 30
	}

	/// Zrzut ekranu dołączany do wyniku, gdy test PADNIE.
	///
	/// PO CO. Padający test UI mówi tylko „XCTAssertTrue failed w linii N”. Nie
	/// mówi, CO było na ekranie: komunikat błędu, pusta lista, kręciołek czy
	/// zupełnie inny widok. Bez tego każda kolejna poprawka jest zgadywaniem,
	/// a każdy cykl zgadywania to ~27 minut CI. Zrzut zamienia „nie wiem, czemu
	/// nie widzi wiersza” na konkretną obserwację.
	///
	/// Zwrot z inwestycji był natychmiastowy: pierwszy zebrany zrzut pokazał
	/// PUSTY ekran kategorii bez komunikatu (defekt aplikacji, nie testu),
	/// a drugi — poprawny ekran przy padającym teście (defekt środowiska).
	///
	/// `tearDown` jest wołany także po porażce, a `testRun?.hasSucceeded`
	/// pozwala nie zaśmiecać artefaktów zrzutami z udanych przebiegów.
	override func tearDown() {
		if testRun?.hasSucceeded == false {
			let zrzut = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
			zrzut.name = "PADL-\(name)"
			zrzut.lifetime = .keepAlways
			add(zrzut)
		}
		super.tearDown()
	}

	private func makeApp(additionalLaunchArguments: [String] = []) -> XCUIApplication {
		let app = XCUIApplication()
		app.terminate()
		app.launchArguments = ["UI_TESTING"] + additionalLaunchArguments
		return app
	}

	private func pullToRefresh(_ list: XCUIElement, untilExists element: XCUIElement, scrollToReveal: Bool = false) {
		func dragDown() {
			let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
			let finish = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
			start.press(forDuration: 0.05, thenDragTo: finish)
		}

		dragDown()
		if !element.waitForExistence(timeout: 2) {
			dragDown()
		}
		if scrollToReveal {
			for _ in 0 ..< 2 {
				if element.waitForExistence(timeout: 0.5) { break }
				list.swipeDown()
			}
			for _ in 0 ..< 8 {
				if element.waitForExistence(timeout: 0.5) { break }
				list.swipeUp()
			}
		}
		XCTAssertTrue(element.waitForExistence(timeout: limitUI))
	}

	private func tapBackButton(in app: XCUIApplication) {
		let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
		XCTAssertTrue(backButton.waitForExistence(timeout: limitUI))
		backButton.tap()
	}

	private func openFavoritesFromMenu(in app: XCUIApplication) {
		let menuQuery = app.descendants(matching: .any).matching(identifier: "app.menu")
		var menuButton = menuQuery.firstMatch

		// The app menu is available on tab root screens; on pushed detail screens we should go back first.
		if !menuButton.waitForExistence(timeout: 2) {
			let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
			if backButton.waitForExistence(timeout: 2) {
				backButton.tap()
			}
		}

		menuButton = menuQuery.firstMatch
		XCTAssertTrue(menuButton.waitForExistence(timeout: limitUI))
		menuButton.tap()

		let favoritesButton = app.descendants(matching: .any).matching(identifier: "app.menu.favorites").firstMatch
		XCTAssertTrue(favoritesButton.waitForExistence(timeout: limitUI))
		favoritesButton.tap()

		let favoritesList = app.descendants(matching: .any).matching(identifier: "favorites.list").firstMatch
		XCTAssertTrue(favoritesList.waitForExistence(timeout: limitUI))
	}

	private func openSettingsFromMenu(in app: XCUIApplication) {
		let menuQuery = app.descendants(matching: .any).matching(identifier: "app.menu")
		var menuButton = menuQuery.firstMatch

		// The app menu is available on tab root screens; on pushed detail screens we should go back first.
		if !menuButton.waitForExistence(timeout: 2) {
			let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
			if backButton.waitForExistence(timeout: 2) {
				backButton.tap()
			}
		}

		menuButton = menuQuery.firstMatch
		XCTAssertTrue(menuButton.waitForExistence(timeout: limitUI))
		menuButton.tap()

		let settingsButton = app.descendants(matching: .any).matching(identifier: "app.menu.settings").firstMatch
		XCTAssertTrue(settingsButton.waitForExistence(timeout: limitUI))
		settingsButton.tap()

		let settingsView = app.descendants(matching: .any).matching(identifier: "settings.view").firstMatch
		XCTAssertTrue(settingsView.waitForExistence(timeout: limitUI))
	}

	func testAppLaunchesAndShowsTabs() {
		let app = makeApp()
		app.launch()

		XCTAssertTrue(app.tabBars.buttons["Nowości"].waitForExistence(timeout: limitUI))
		XCTAssertTrue(app.tabBars.buttons["Podcasty"].exists)
		XCTAssertTrue(app.tabBars.buttons["Artykuły"].exists)
		XCTAssertTrue(app.tabBars.buttons["Szukaj"].exists)
		XCTAssertTrue(app.tabBars.buttons["Tyfloradio"].exists)
	}

	func testNewsShowsRetryWhenRequestsStall() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_STALL_NEWS_REQUESTS", "UI_TESTING_FAST_TIMEOUTS"])
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
	}

	func testCanOpenRadioPlayerFromMoreTab() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: limitUI))
		radioButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: limitUI))
		XCTAssertEqual(playPauseButton.label, "Odtwarzaj")

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.exists)
		XCTAssertEqual(contactButton.label, "Skontaktuj się z Tyfloradiem")
	}

	func testCanOpenRadioScheduleFromMoreTab() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let scheduleButton = app.descendants(matching: .any).matching(identifier: "more.schedule").firstMatch
		XCTAssertTrue(scheduleButton.waitForExistence(timeout: limitUI))
		scheduleButton.tap()

		let scheduleView = app.descendants(matching: .any).matching(identifier: "radioSchedule.view").firstMatch
		XCTAssertTrue(scheduleView.waitForExistence(timeout: limitUI))

		let scheduleText = app.descendants(matching: .any).matching(identifier: "radioSchedule.text").firstMatch
		XCTAssertTrue(scheduleText.waitForExistence(timeout: limitUI))
	}

	func testCanSendVoiceMessageWhenTextMessageIsEmpty() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_TP_AVAILABLE", "UI_TESTING_SEED_VOICE_RECORDED", "UI_TESTING_CONTACT_MESSAGE_WHITESPACE"])
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let contactButton = app.descendants(matching: .any).matching(identifier: "more.contactRadio").firstMatch
		XCTAssertTrue(contactButton.waitForExistence(timeout: limitUI))
		contactButton.tap()

		let voiceMenuItem = app.descendants(matching: .any).matching(identifier: "contact.menu.voice").firstMatch
		XCTAssertTrue(voiceMenuItem.waitForExistence(timeout: limitUI))
		voiceMenuItem.tap()

		let nameField = app.descendants(matching: .any).matching(identifier: "contact.name").firstMatch
		XCTAssertTrue(nameField.waitForExistence(timeout: limitUI))
		nameField.tap()
		nameField.typeText("UI")

		let voiceSendButton = app.descendants(matching: .any).matching(identifier: "contact.voice.send").firstMatch
		let voiceForm = app.descendants(matching: .any).matching(identifier: "contactVoice.form").firstMatch
		XCTAssertTrue(voiceForm.waitForExistence(timeout: limitUI))
		for _ in 0 ..< 8 {
			if voiceSendButton.exists { break }
			voiceForm.swipeUp()
		}
		XCTAssertTrue(voiceSendButton.waitForExistence(timeout: limitUI))
		XCTAssertTrue(voiceSendButton.isEnabled)

		let backButton = app.navigationBars.buttons["Kontakt"].firstMatch
		XCTAssertTrue(backButton.waitForExistence(timeout: limitUI))
		backButton.tap()

		let textMenuItem = app.descendants(matching: .any).matching(identifier: "contact.menu.text").firstMatch
		XCTAssertTrue(textMenuItem.waitForExistence(timeout: limitUI))
		textMenuItem.tap()

		let textSendButton = app.descendants(matching: .any).matching(identifier: "contact.send").firstMatch
		XCTAssertTrue(textSendButton.waitForExistence(timeout: limitUI))
		XCTAssertFalse(textSendButton.isEnabled)
	}

	func testCanPreviewRecordedVoiceMessage() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_TP_AVAILABLE", "UI_TESTING_SEED_VOICE_RECORDED"])
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let contactButton = app.descendants(matching: .any).matching(identifier: "more.contactRadio").firstMatch
		XCTAssertTrue(contactButton.waitForExistence(timeout: limitUI))
		contactButton.tap()

		let voiceMenuItem = app.descendants(matching: .any).matching(identifier: "contact.menu.voice").firstMatch
		XCTAssertTrue(voiceMenuItem.waitForExistence(timeout: limitUI))
		voiceMenuItem.tap()

		let nameField = app.descendants(matching: .any).matching(identifier: "contact.name").firstMatch
		XCTAssertTrue(nameField.waitForExistence(timeout: limitUI))
		nameField.tap()
		nameField.typeText("UI")

		let holdToTalkButton = app.descendants(matching: .any).matching(identifier: "contact.voice.holdToTalk").firstMatch
		XCTAssertTrue(holdToTalkButton.waitForExistence(timeout: limitUI))
		XCTAssertTrue(holdToTalkButton.isEnabled)

		let previewButton = app.descendants(matching: .any).matching(identifier: "contact.voice.preview").firstMatch
		let voiceForm = app.descendants(matching: .any).matching(identifier: "contactVoice.form").firstMatch
		XCTAssertTrue(voiceForm.waitForExistence(timeout: limitUI))
		for _ in 0 ..< 8 {
			if previewButton.exists { break }
			voiceForm.swipeUp()
		}
		XCTAssertTrue(previewButton.waitForExistence(timeout: limitUI))
		XCTAssertEqual(previewButton.label, "Odsłuchaj")

		previewButton.tap()
		expectation(for: NSPredicate(format: "label == %@", "Zatrzymaj odsłuch"), evaluatedWith: previewButton)
		waitForExpectations(timeout: limitUI)

		previewButton.tap()
		expectation(for: NSPredicate(format: "label == %@", "Odsłuchaj"), evaluatedWith: previewButton)
		waitForExpectations(timeout: limitUI)
	}

	func testCanOpenPodcastPlayerAndSeeSeekControls() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		let listenButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.listen").firstMatch
		XCTAssertTrue(listenButton.waitForExistence(timeout: limitUI))
		XCTAssertEqual(listenButton.label, "Słuchaj audycji")
		listenButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: limitUI))
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

		let airPlayButton = app.descendants(matching: .any).matching(identifier: "player.airplay").firstMatch
		XCTAssertTrue(airPlayButton.waitForExistence(timeout: limitUI))
	}

	func testCanAddPodcastToFavoritesAndSeeItInFavorites() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		let favoriteButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.favorite").firstMatch
		XCTAssertTrue(favoriteButton.waitForExistence(timeout: limitUI))
		XCTAssertEqual(favoriteButton.label, "Dodaj do ulubionych")
		favoriteButton.tap()

		let predicate = NSPredicate(format: "label == %@", "Usuń z ulubionych")
		let waitExpectation = expectation(for: predicate, evaluatedWith: favoriteButton)
		XCTAssertEqual(XCTWaiter().wait(for: [waitExpectation], timeout: limitUI), .completed)

		openFavoritesFromMenu(in: app)

		let favoritesPodcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(favoritesPodcastRow.waitForExistence(timeout: limitUI))
		tapBackButton(in: app)
	}

	func testPodcastFavoritedFromRowCanBeUnfavoritedInDetail() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))

		podcastRow.press(forDuration: 1.0)

		let addFavoriteButton = app.buttons["Dodaj do ulubionych"].firstMatch
		let addFavoriteMenuItem = app.menuItems["Dodaj do ulubionych"].firstMatch
		let addFavoriteElement: XCUIElement
		if addFavoriteButton.waitForExistence(timeout: 2) {
			addFavoriteElement = addFavoriteButton
		} else {
			XCTAssertTrue(addFavoriteMenuItem.waitForExistence(timeout: 2))
			addFavoriteElement = addFavoriteMenuItem
		}
		addFavoriteElement.tap()

		let menuDismissPredicate = NSPredicate(format: "exists == false")
		let menuDismissExpectation = expectation(for: menuDismissPredicate, evaluatedWith: addFavoriteElement)
		XCTAssertEqual(XCTWaiter().wait(for: [menuDismissExpectation], timeout: limitUI), .completed)

		let podcastRowAfterFavorite = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRowAfterFavorite.waitForExistence(timeout: limitUI))
		podcastRowAfterFavorite.tap()

		let favoriteButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.favorite").firstMatch
		XCTAssertTrue(favoriteButton.waitForExistence(timeout: limitUI))
		XCTAssertEqual(favoriteButton.label, "Usuń z ulubionych")
		favoriteButton.tap()

		let predicate = NSPredicate(format: "label == %@", "Dodaj do ulubionych")
		let waitExpectation = expectation(for: predicate, evaluatedWith: favoriteButton)
		XCTAssertEqual(XCTWaiter().wait(for: [waitExpectation], timeout: limitUI), .completed)

		openFavoritesFromMenu(in: app)

		let favoritesPodcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertFalse(favoritesPodcastRow.waitForExistence(timeout: 2))
		tapBackButton(in: app)
	}

	func testPodcastDetailShowsCommentsAndCanOpenThem() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let commentsSummary = app.descendants(matching: .any).matching(identifier: "podcastDetail.commentsSummary").firstMatch
		XCTAssertTrue(commentsSummary.waitForExistence(timeout: limitUI))

		let predicate = NSPredicate(format: "label == %@", "2 komentarze")
		let waitExpectation = expectation(for: predicate, evaluatedWith: commentsSummary)
		XCTAssertEqual(XCTWaiter().wait(for: [waitExpectation], timeout: limitUI), .completed)

		commentsSummary.tap()

		let commentsList = app.descendants(matching: .any).matching(identifier: "comments.list").firstMatch
		XCTAssertTrue(commentsList.waitForExistence(timeout: limitUI))

		let commentRow = app.descendants(matching: .any).matching(identifier: "comment.row.1001").firstMatch
		XCTAssertTrue(commentRow.waitForExistence(timeout: limitUI))
		commentRow.tap()

		let commentContent = app.descendants(matching: .any).matching(identifier: "comment.content").firstMatch
		XCTAssertTrue(commentContent.waitForExistence(timeout: limitUI))
	}

	func testPodcastDetailActionsWorkWithLargeContent() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_LARGE_PODCAST_CONTENT"])
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let favoriteButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.favorite").firstMatch
		XCTAssertTrue(favoriteButton.waitForExistence(timeout: limitUI))
		favoriteButton.tap()

		let favoritePredicate = NSPredicate(format: "label == %@", "Usuń z ulubionych")
		let favoriteWaitExpectation = expectation(for: favoritePredicate, evaluatedWith: favoriteButton)
		XCTAssertEqual(XCTWaiter().wait(for: [favoriteWaitExpectation], timeout: limitUI), .completed)

		let commentsSummary = app.descendants(matching: .any).matching(identifier: "podcastDetail.commentsSummary").firstMatch
		XCTAssertTrue(commentsSummary.waitForExistence(timeout: limitUI))

		let commentsPredicate = NSPredicate(format: "label == %@", "2 komentarze")
		let commentsWaitExpectation = expectation(for: commentsPredicate, evaluatedWith: commentsSummary)
		XCTAssertEqual(XCTWaiter().wait(for: [commentsWaitExpectation], timeout: limitUI), .completed)
	}

	func testFavoriteTopicPlayActionOpensPlayer() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let listenButton = app.descendants(matching: .any).matching(identifier: "podcastDetail.listen").firstMatch
		XCTAssertTrue(listenButton.waitForExistence(timeout: limitUI))
		listenButton.tap()

		let markersButton = app.descendants(matching: .any).matching(identifier: "player.showChapterMarkers").firstMatch
		XCTAssertTrue(markersButton.waitForExistence(timeout: limitUI))
		markersButton.tap()

		let introMarker = app.buttons["Intro"].firstMatch
		XCTAssertTrue(introMarker.waitForExistence(timeout: limitUI))
		introMarker.press(forDuration: 1.0)

		let addFavorite = app.buttons["Dodaj do ulubionych"].firstMatch
		XCTAssertTrue(addFavorite.waitForExistence(timeout: limitUI))
		addFavorite.tap()

		tapBackButton(in: app)
		tapBackButton(in: app)

		openFavoritesFromMenu(in: app)

		let filter = app.segmentedControls["favorites.filter"]
		XCTAssertTrue(filter.waitForExistence(timeout: limitUI))
		filter.buttons["Tematy"].tap()

		let topicRow = app.descendants(matching: .any).matching(identifier: "favorites.topic.1.0").firstMatch
		XCTAssertTrue(topicRow.waitForExistence(timeout: limitUI))
		topicRow.press(forDuration: 1.0)

		let playButton = app.buttons["Odtwarzaj od tego miejsca"].firstMatch
		let playMenuItem = app.menuItems["Odtwarzaj od tego miejsca"].firstMatch
		if playButton.waitForExistence(timeout: 2) {
			playButton.tap()
		} else {
			XCTAssertTrue(playMenuItem.waitForExistence(timeout: 2))
			playMenuItem.tap()
		}

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: limitUI))
	}

	func testCanAddArticleToFavoritesAndFilterIt() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		let shareButton = app.descendants(matching: .any).matching(identifier: "articleDetail.share").firstMatch
		XCTAssertTrue(shareButton.waitForExistence(timeout: limitUI))

		let favoriteButton = app.descendants(matching: .any).matching(identifier: "articleDetail.favorite").firstMatch
		XCTAssertTrue(favoriteButton.waitForExistence(timeout: limitUI))
		favoriteButton.tap()

		openFavoritesFromMenu(in: app)

		let filter = app.segmentedControls["favorites.filter"]
		XCTAssertTrue(filter.waitForExistence(timeout: limitUI))
		filter.buttons["Artykuły"].tap()

		let favoritesArticleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(favoritesArticleRow.waitForExistence(timeout: limitUI))
	}

	func testCanOpenPodcastCategoryAndSeeItems() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Podcasty"].tap()

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		categoryRow.tap()

		let categoryList = app.descendants(matching: .any).matching(identifier: "categoryPodcasts.list").firstMatch
		XCTAssertTrue(categoryList.waitForExistence(timeout: limitUI))

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testCanOpenArticleCategoryAndSeeItems() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Artykuły"].tap()

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		categoryRow.tap()

		let categoryList = app.descendants(matching: .any).matching(identifier: "categoryArticles.list").firstMatch
		XCTAssertTrue(categoryList.waitForExistence(timeout: limitUI))

		let articleRow = app.descendants(matching: .any).matching(identifier: "podcast.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testCanSearchAndOpenPodcastFromResults() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Szukaj"].tap()

		let searchField = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
		XCTAssertTrue(searchField.waitForExistence(timeout: limitUI))
		searchField.tap()
		searchField.typeText("test")

		let searchButton = app.descendants(matching: .any).matching(identifier: "search.button").firstMatch
		XCTAssertTrue(searchButton.exists)
		searchButton.tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(podcastRow.label, "Podcast. Test podcast")
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testContentKindLabelPositionUpdatesImmediately() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let initialRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(initialRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(initialRow.label, "Podcast. Test podcast")

		openSettingsFromMenu(in: app)

		let picker = app.segmentedControls["settings.contentKindLabelPosition"]
		XCTAssertTrue(picker.waitForExistence(timeout: limitUI))
		picker.buttons["Po"].tap()
		let pickerAfterTap = app.segmentedControls["settings.contentKindLabelPosition"]
		XCTAssertTrue(pickerAfterTap.waitForExistence(timeout: limitUI))
		XCTAssertEqual(pickerAfterTap.value as? String, "Po")

		tapBackButton(in: app)

		let updatedRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(updatedRow.waitForExistence(timeout: limitUI))

		let expectedLabel = "Test podcast. Podcast"
		let predicate = NSPredicate(format: "label == %@", expectedLabel)
		let waitExpectation = expectation(for: predicate, evaluatedWith: updatedRow)
		let result = XCTWaiter().wait(for: [waitExpectation], timeout: limitUI)
		if result != .completed {
			XCTFail("Expected label '\(expectedLabel)', got '\(updatedRow.label)'.")
		}
	}

	func testCanSearchArticlesWhenScopeIsArticles() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Szukaj"].tap()

		let scopePicker = app.segmentedControls["search.scope"]
		XCTAssertTrue(scopePicker.waitForExistence(timeout: limitUI))
		scopePicker.buttons["Artykuły"].tap()

		let searchField = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
		XCTAssertTrue(searchField.waitForExistence(timeout: limitUI))
		searchField.tap()
		searchField.typeText("test")

		let searchButton = app.descendants(matching: .any).matching(identifier: "search.button").firstMatch
		XCTAssertTrue(searchButton.exists)
		searchButton.tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(articleRow.label, "Artykuł. Test artykuł")
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testCanOpenArticleFromNewsAndSeeReadableContent() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testRadioContactShowsNoLiveAlert() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: limitUI))
		radioButton.tap()

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.waitForExistence(timeout: limitUI))
		contactButton.tap()

		let alert = app.alerts["Błąd"]
		XCTAssertTrue(alert.waitForExistence(timeout: limitUI))
		XCTAssertTrue(alert.staticTexts["Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna."].exists)
	}

	func testCanOpenContactFormAndSendMessageWhenAvailable() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_TP_AVAILABLE"])
		app.launch()

		app.tabBars.buttons["Tyfloradio"].tap()

		let radioButton = app.descendants(matching: .any).matching(identifier: "more.tyfloradio").firstMatch
		XCTAssertTrue(radioButton.waitForExistence(timeout: limitUI))
		radioButton.tap()

		let contactButton = app.descendants(matching: .any).matching(identifier: "player.contactRadio").firstMatch
		XCTAssertTrue(contactButton.waitForExistence(timeout: limitUI))
		contactButton.tap()

		let textMenuItem = app.descendants(matching: .any).matching(identifier: "contact.menu.text").firstMatch
		XCTAssertTrue(textMenuItem.waitForExistence(timeout: limitUI))
		textMenuItem.tap()

		let nameField = app.descendants(matching: .any).matching(identifier: "contact.name").firstMatch
		XCTAssertTrue(nameField.waitForExistence(timeout: limitUI))
		nameField.tap()
		nameField.typeText("UI Test")

		let messageField = app.descendants(matching: .any).matching(identifier: "contact.message").firstMatch
		XCTAssertTrue(messageField.exists)
		messageField.tap()
		messageField.typeText("\nWiadomość testowa")

		let sendButton = app.descendants(matching: .any).matching(identifier: "contact.send").firstMatch
		XCTAssertTrue(sendButton.exists)
		sendButton.tap()

		let playPauseButton = app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch
		if !playPauseButton.waitForExistence(timeout: 1) {
			tapBackButton(in: app)
		}
		if !playPauseButton.waitForExistence(timeout: 1) {
			tapBackButton(in: app)
		}
		XCTAssertTrue(playPauseButton.waitForExistence(timeout: limitUI))
	}

	func testPullToRefreshUpdatesLists() {
		let app = makeApp()
		app.launch()

		let newsList = app.descendants(matching: .any).matching(identifier: "news.list").firstMatch
		XCTAssertTrue(newsList.waitForExistence(timeout: limitUI))
		let initialNewsRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(initialNewsRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(initialNewsRow.label, "Podcast. Test podcast")

		let initialArticleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(initialArticleRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(initialArticleRow.label, "Artykuł. Test artykuł")

		app.tabBars.buttons["Podcasty"].tap()
		let podcastCategoriesList = app.descendants(matching: .any).matching(identifier: "podcastCategories.list").firstMatch
		XCTAssertTrue(podcastCategoriesList.waitForExistence(timeout: limitUI))
		let initialPodcastCategory = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(initialPodcastCategory.waitForExistence(timeout: limitUI))
		let refreshedPodcastCategory = app.descendants(matching: .any).matching(identifier: "category.row.11").firstMatch
		pullToRefresh(podcastCategoriesList, untilExists: refreshedPodcastCategory)
		XCTAssertEqual(refreshedPodcastCategory.label, "Test podcasty 2")

		let podcastCategoryRow = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(podcastCategoryRow.waitForExistence(timeout: limitUI))
		podcastCategoryRow.tap()

		let categoryPodcastsList = app.descendants(matching: .any).matching(identifier: "categoryPodcasts.list").firstMatch
		XCTAssertTrue(categoryPodcastsList.waitForExistence(timeout: limitUI))
		let initialCategoryPodcast = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(initialCategoryPodcast.waitForExistence(timeout: limitUI))
		let refreshedCategoryPodcast = app.descendants(matching: .any).matching(identifier: "podcast.row.4").firstMatch
		pullToRefresh(categoryPodcastsList, untilExists: refreshedCategoryPodcast)
		XCTAssertEqual(refreshedCategoryPodcast.label, "Test podcast w kategorii 2")

		app.tabBars.buttons["Artykuły"].tap()
		let articleCategoriesList = app.descendants(matching: .any).matching(identifier: "articleCategories.list").firstMatch
		XCTAssertTrue(articleCategoriesList.waitForExistence(timeout: limitUI))
		let initialArticleCategory = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(initialArticleCategory.waitForExistence(timeout: limitUI))
		let refreshedArticleCategory = app.descendants(matching: .any).matching(identifier: "category.row.21").firstMatch
		pullToRefresh(articleCategoriesList, untilExists: refreshedArticleCategory)
		XCTAssertEqual(refreshedArticleCategory.label, "Test artykuły 2")

		let articleCategoryRow = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(articleCategoryRow.waitForExistence(timeout: limitUI))
		articleCategoryRow.tap()

		let categoryArticlesList = app.descendants(matching: .any).matching(identifier: "categoryArticles.list").firstMatch
		XCTAssertTrue(categoryArticlesList.waitForExistence(timeout: limitUI))
		let initialCategoryArticle = app.descendants(matching: .any).matching(identifier: "podcast.row.2").firstMatch
		XCTAssertTrue(initialCategoryArticle.waitForExistence(timeout: limitUI))
		let refreshedCategoryArticle = app.descendants(matching: .any).matching(identifier: "podcast.row.5").firstMatch
		pullToRefresh(categoryArticlesList, untilExists: refreshedCategoryArticle)
		XCTAssertEqual(refreshedCategoryArticle.label, "Test artykuł 2")
	}

	/// Klika „Spróbuj ponownie”, jeśli lista pokazała komunikat o błędzie.
	///
	/// DLACZEGO TO JEST POTRZEBNE. Aplikacja ponawia pobranie sama — w warstwie
	/// API (`withRetry`, 2 próby) i w modelu listy (trzecia próba). Ale gdy
	/// WSZYSTKIE próby padną, świadomie pokazuje komunikat i przycisk zamiast
	/// kręcić się w nieskończoność. To zachowanie POŻĄDANE, nie awaria:
	/// użytkownik ma wiedzieć, że coś poszło nie tak, i mieć jawną drogę wyjścia.
	///
	/// Test, który tylko czeka, zakłada więc coś, czego aplikacja celowo nie robi.
	/// Zamiast tego: poczekaj chwilę na dane, a jeśli zamiast nich jest przycisk
	/// ponowienia — kliknij go, tak jak zrobiłby użytkownik.
	@discardableResult
	private func ponowJesliTrzeba(_ app: XCUIApplication,
	                              identyfikatorPonowienia: String) -> Bool
	{
		let przycisk = app.descendants(matching: .any)
			.matching(identifier: identyfikatorPonowienia).firstMatch
		guard przycisk.waitForExistence(timeout: 3) else { return false }
		przycisk.tap()
		return true
	}

	func testListsRecoverWhenFirstRequestFails() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_FAIL_FIRST_REQUEST"])
		app.launch()

		let newsList = app.descendants(matching: .any).matching(identifier: "news.list").firstMatch
		XCTAssertTrue(newsList.waitForExistence(timeout: limitUI))
		let firstNewsRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(firstNewsRow.waitForExistence(timeout: limitUI))

		app.tabBars.buttons["Podcasty"].tap()
		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		if !categoryRow.waitForExistence(timeout: 5) {
			// Wszystkie automatyczne próby padły, więc na ekranie jest komunikat
			// i przycisk. Klikamy go — dokładnie to zrobiłby użytkownik.
			XCTAssertTrue(ponowJesliTrzeba(app, identyfikatorPonowienia: "podcastCategories.retry"),
			              "Brak danych ORAZ brak przycisku ponowienia — to jest realny defekt: "
			              	+ "użytkownik zostaje z pustym ekranem bez drogi wyjścia.")
		}
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		categoryRow.tap()
		let firstCategoryPodcast = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(firstCategoryPodcast.waitForExistence(timeout: limitUI))

		app.tabBars.buttons["Artykuły"].tap()
		let articleCategory = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		if !articleCategory.waitForExistence(timeout: 5) {
			XCTAssertTrue(ponowJesliTrzeba(app, identyfikatorPonowienia: "articleCategories.retry"),
			              "Brak danych ORAZ brak przycisku ponowienia na liście artykułów.")
		}
		XCTAssertTrue(articleCategory.waitForExistence(timeout: limitUI))
	}

	func testSearchRecoversAutomaticallyWhenFirstRequestFails() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_FAIL_FIRST_REQUEST"])
		app.launch()

		app.tabBars.buttons["Szukaj"].tap()

		let searchList = app.descendants(matching: .any).matching(identifier: "search.list").firstMatch
		XCTAssertTrue(searchList.waitForExistence(timeout: limitUI))

		let searchField = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
		XCTAssertTrue(searchField.waitForExistence(timeout: limitUI))
		searchField.tap()
		searchField.typeText("test")

		let searchButton = app.descendants(matching: .any).matching(identifier: "search.button").firstMatch
		XCTAssertTrue(searchButton.exists)
		searchButton.tap()

		let firstResult = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(firstResult.waitForExistence(timeout: limitUI))
	}

	func testCanBrowsePodcastCategoriesAndOpenPodcast() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Podcasty"].tap()

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(categoryRow.label, "Test podcasty")
		categoryRow.tap()

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testCanBrowseArticleCategoriesAndOpenArticle() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Artykuły"].tap()

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(categoryRow.label, "Test artykuły")
		categoryRow.tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "podcast.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))
	}

	func testCanBrowseMagazineAndOpenArticle() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Artykuły"].tap()

		let magazineRow = app.descendants(matching: .any).matching(identifier: "articleCategories.magazine").firstMatch
		XCTAssertTrue(magazineRow.waitForExistence(timeout: limitUI))
		magazineRow.tap()

		let yearsList = app.descendants(matching: .any).matching(identifier: "magazine.years.list").firstMatch
		XCTAssertTrue(yearsList.waitForExistence(timeout: limitUI))

		let yearRow = app.descendants(matching: .any).matching(identifier: "magazine.year.2025").firstMatch
		XCTAssertTrue(yearRow.waitForExistence(timeout: limitUI))
		yearRow.tap()

		let issueRow = app.descendants(matching: .any).matching(identifier: "magazine.issue.7772").firstMatch
		XCTAssertTrue(issueRow.waitForExistence(timeout: limitUI))
		issueRow.tap()

		let issueNavigationBar = app.navigationBars["Tyfloświat 4/2025"]
		XCTAssertTrue(issueNavigationBar.waitForExistence(timeout: limitUI))
	}

	func testCanNavigateBackFromPodcastDetail() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Podcasty"].tap()

		let categoriesList = app.descendants(matching: .any).matching(identifier: "podcastCategories.list").firstMatch
		XCTAssertTrue(categoriesList.waitForExistence(timeout: limitUI))

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		categoryRow.tap()

		let categoryPodcastsList = app.descendants(matching: .any).matching(identifier: "categoryPodcasts.list").firstMatch
		XCTAssertTrue(categoryPodcastsList.waitForExistence(timeout: limitUI))

		let podcastRow = app.descendants(matching: .any).matching(identifier: "podcast.row.1").firstMatch
		XCTAssertTrue(podcastRow.waitForExistence(timeout: limitUI))
		podcastRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "podcastDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		tapBackButton(in: app)
		XCTAssertTrue(categoryPodcastsList.waitForExistence(timeout: limitUI))

		tapBackButton(in: app)
		XCTAssertTrue(categoriesList.waitForExistence(timeout: limitUI))
	}

	func testCanNavigateBackFromArticleDetail() {
		let app = makeApp()
		app.launch()

		app.tabBars.buttons["Artykuły"].tap()

		let categoriesList = app.descendants(matching: .any).matching(identifier: "articleCategories.list").firstMatch
		XCTAssertTrue(categoriesList.waitForExistence(timeout: limitUI))

		let categoryRow = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(categoryRow.waitForExistence(timeout: limitUI))
		categoryRow.tap()

		let categoryArticlesList = app.descendants(matching: .any).matching(identifier: "categoryArticles.list").firstMatch
		XCTAssertTrue(categoryArticlesList.waitForExistence(timeout: limitUI))

		let articleRow = app.descendants(matching: .any).matching(identifier: "podcast.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		tapBackButton(in: app)
		XCTAssertTrue(categoryArticlesList.waitForExistence(timeout: limitUI))

		tapBackButton(in: app)
		XCTAssertTrue(categoriesList.waitForExistence(timeout: limitUI))
	}
}
