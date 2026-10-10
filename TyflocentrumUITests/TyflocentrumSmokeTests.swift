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
		// DLACZEGO NIE MA TU `app.terminate()`. Na przeciążonym runnerze rzuca
		// „Failed to terminate net.tyflopodcast.tyflocentrum:8080: Failed to terminate …:0”
		// i wywala test JESZCZE PRZED jego pierwszą linią — zmierzone w run
		// 33814048157, gdzie padło dokładnie w tej linii, a wcześniejsze przebiegi
		// wywalały się w INNYCH, losowych testach (sygnatura chwiejnego
		// środowiska, nie defektu aplikacji). Pojedyncze operacje zajmowały tam
		// do 57 s.
		//
		// Owinięcie w `XCTContext.runActivity` NIE POMOGŁOBY: to jest tylko
		// grupowanie w raporcie, nie przechwytywanie błędów — XCTest nadal
		// zgłosiłby porażkę.
		//
		// Terminate było tu sprzątaniem stanu przed startem, ale jest ZBĘDNE.
		// Dokumentacja Apple dla `XCUIApplication.launch()` mówi wprost: „If the
		// application is already running, this call terminates the existing
		// instance, to ensure a clean launch state for the newly launched
		// instance”. Czyli usunięcie tej linii nie zmienia izolacji testów —
		// usuwa tylko drugie, zawodne wywołanie tej samej operacji.
		app.launchArguments = ["UI_TESTING"] + additionalLaunchArguments
		return app
	}

	private let articleTitleParagraph = "Kontrolny akapit pełnej treści z polskimi znakami: żółw i źdźbło."
	private let articleLongTitle = "Zażółć gęślą jaźń & dostępność: pełny, bardzo długi tytuł artykułu o czytaniu, nawigacji i zachowaniu polskich znaków na ekranie telefonu"

	private func saveTitleEvidence(_ app: XCUIApplication, route: String) -> [[String: Any]] {
		let capture = app.buttons["titleTest.capture"]
		XCTAssertTrue(capture.waitForExistence(timeout: limitUI))
		capture.tap()
		let raw = capture.value as? String ?? "[]"
		for (name, text) in [("\(route)-xcui", app.debugDescription), ("\(route)-traits", raw)] {
			let attachment = XCTAttachment(string: text)
			attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
		}
		let screenshot = XCTAttachment(screenshot: app.screenshot())
		screenshot.name = route; screenshot.lifetime = .keepAlways; add(screenshot)
		return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[String: Any]] ?? []
	}

	private func checkArticleHeader(_ app: XCUIApplication, title: String, route: String, traits: [[String: Any]]) {
		let header = app.descendants(matching: .any).matching(identifier: "articleDetail.header").firstMatch
		XCTAssertTrue(header.exists)
		// Liczymy użytkowe miejsca, nie powtarzające etykietę kontenery AX.
		let bodyTitleCount = header.label.contains(title) ? 1 : 0
		let navigationTitleCount = app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", title)).count
		let htmlTitleCount = app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", title)).count
		let counts = "body=\(bodyTitleCount);navigation=\(navigationTitleCount);html=\(htmlTitleCount)"
		let attachment = XCTAttachment(string: counts)
		attachment.name = "\(route)-counts"; attachment.lifetime = .keepAlways; add(attachment)
		XCTAssertEqual(bodyTitleCount + navigationTitleCount + htmlTitleCount, 1, "SINGLE_ARTICLE_TITLE: \(counts)")
		XCTAssertEqual(header.label, title, "Pełny tytuł bez daty")
		let date = app.staticTexts["articleDetail.date"]
		XCTAssertTrue(date.exists, "Data jest osobnym elementem")
		XCTAssertFalse(date.label.isEmpty)
		// AccessibilityNode nie eksportuje identyfikatora przez protokół UIKit (pomiar F1).
		// Wiążemy odczyt cech z pełną, unikalną etykietą i niezależnym ID w XCUI.
		let titleNodes = traits.filter { ($0["label"] as? String) == title }
		let dateNodes = traits.filter { ($0["label"] as? String) == date.label }
		XCTAssertEqual(titleNodes.count, 1, "Jeden rzeczywisty element UIAccessibility tytułu")
		XCTAssertEqual(titleNodes.first?["header"] as? Bool, true)
		XCTAssertEqual(dateNodes.count, 1)
		XCTAssertEqual(dateNodes.first?["header"] as? Bool, false)
	}

	private func checkSingleArticleTitle(_ app: XCUIApplication, title: String, route: String, actions: Bool = true) {
		let paragraph = app.webViews.staticTexts[articleTitleParagraph].firstMatch
		XCTAssertTrue(paragraph.waitForExistence(timeout: limitUI), "Rzeczywisty akapit WKWebView")
		let traits = saveTitleEvidence(app, route: route)
		checkArticleHeader(app, title: title, route: route, traits: traits)
		XCTAssertTrue(app.webViews.staticTexts[title + " w praktyce"].exists, "Podobny śródtytuł pozostaje")
		XCTAssertTrue(app.webViews.staticTexts["Dalsze wskazówki"].exists)
		let h2 = app.webViews.otherElements.matching(NSPredicate(format: "label == %@", title + " w praktyce")).firstMatch
		let h3 = app.webViews.otherElements.matching(NSPredicate(format: "label == %@", "Dalsze wskazówki")).firstMatch
		XCTAssertEqual(String(describing: h2.value ?? ""), "2", "Poziom nagłówka h2 w AX WebKita")
		XCTAssertEqual(String(describing: h3.value ?? ""), "3", "Poziom nagłówka h3 w AX WebKita")
		XCTAssertTrue(app.webViews.staticTexts["Drugi akapit pozostaje bez zmian."].exists)
		XCTAssertTrue(app.buttons["articleDetail.favorite"].isHittable)
		XCTAssertTrue(app.buttons["articleDetail.share"].isHittable)
		if actions {
			let favorite = app.buttons["articleDetail.favorite"]
			let initial = favorite.label
			favorite.tap()
			let changed = initial == "Dodaj do ulubionych" ? "Usuń z ulubionych" : "Dodaj do ulubionych"
			let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", changed), object: favorite)
			XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: limitUI), .completed)
			favorite.tap()
			let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", initial), object: favorite)
			XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: limitUI), .completed)
			app.buttons["articleDetail.share"].tap()
			let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Zamknij"])).firstMatch
			let sheetReady = close.waitForExistence(timeout: limitUI)
			let sheetAX = XCTAttachment(string: app.debugDescription)
			sheetAX.name = "\(route)-share-xcui"; sheetAX.lifetime = .keepAlways; add(sheetAX)
			let sheetImage = XCTAttachment(screenshot: app.screenshot())
			sheetImage.name = "\(route)-share"; sheetImage.lifetime = .keepAlways; add(sheetImage)
			XCTAssertTrue(sheetReady, "Systemowy arkusz udostępniania ma przycisk zamknięcia")
			close.tap()
			XCTAssertTrue(app.buttons["articleDetail.share"].waitForExistence(timeout: limitUI))
		}
	}

	private func titleApp(_ extra: [String] = []) -> XCUIApplication {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_ARTICLE_TITLE"] + extra)
		app.launch()
		return app
	}

	private func tapTitleRow(_ app: XCUIApplication, _ id: String) {
		let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
		XCTAssertTrue(row.waitForExistence(timeout: limitUI), id)
		row.tap()
	}

	func testSingleArticleTitleNews() {
		let app = titleApp()
		tapTitleRow(app, "article.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-news")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "news.list").firstMatch.exists)
		tapTitleRow(app, "article.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-news-reentry", actions: false)
	}

	func testSingleArticleTitleAllLong() {
		let app = titleApp(["UI_TESTING_LONG_ARTICLE_TITLE"])
		app.tabBars.buttons["Artykuły"].tap()
		tapTitleRow(app, "articleCategories.all")
		tapTitleRow(app, "podcast.row.2")
		checkSingleArticleTitle(app, title: articleLongTitle, route: "title-all-long")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "allArticles.list").firstMatch.exists)
	}

	func testSingleArticleTitleCategory() {
		let app = titleApp()
		app.tabBars.buttons["Artykuły"].tap()
		tapTitleRow(app, "category.row.20")
		tapTitleRow(app, "podcast.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-category")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "categoryArticles.list").firstMatch.exists)
	}

	func testSingleArticleTitleSearch() {
		let app = titleApp()
		app.tabBars.buttons["Szukaj"].tap()
		let field = app.textFields["search.field"]
		XCTAssertTrue(field.waitForExistence(timeout: limitUI))
		field.tap(); field.typeText("test")
		app.buttons["search.button"].tap()
		tapTitleRow(app, "article.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-search")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "search.list").firstMatch.exists)
		XCTAssertEqual(field.value as? String, "test")
	}

	func testSingleArticleTitleFavoritesPost() {
		let app = titleApp()
		tapTitleRow(app, "article.row.2")
		let favorite = app.buttons["articleDetail.favorite"]
		XCTAssertTrue(favorite.waitForExistence(timeout: limitUI)); favorite.tap()
		tapBackButton(in: app)
		openFavoritesFromMenu(in: app)
		tapTitleRow(app, "article.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-favorites-post")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "favorites.list").firstMatch.exists)
	}

	private func openTitleIssue(_ app: XCUIApplication) {
		app.tabBars.buttons["Artykuły"].tap()
		tapTitleRow(app, "articleCategories.magazine")
		tapTitleRow(app, "magazine.year.2025")
		tapTitleRow(app, "magazine.issue.7772")
	}

	func testSingleArticleTitleMagazineAndFavoritesPage() {
		let app = titleApp(["UI_TESTING_LONG_ARTICLE_TITLE"])
		openTitleIssue(app)
		tapTitleRow(app, "magazine.article.7774")
		checkSingleArticleTitle(app, title: articleLongTitle, route: "title-magazine-page")
		app.buttons["articleDetail.favorite"].tap()
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "magazine.toc.list").firstMatch.exists)
		tapBackButton(in: app); tapBackButton(in: app); tapBackButton(in: app)
		openFavoritesFromMenu(in: app)
		tapTitleRow(app, "article.row.7774")
		checkSingleArticleTitle(app, title: articleLongTitle, route: "title-favorites-page")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "favorites.list").firstMatch.exists)
	}

	func testSingleArticleTitleMagazineWithoutContents() {
		let app = titleApp(["UI_TESTING_EMPTY_ISSUE"])
		openTitleIssue(app)
		checkSingleArticleTitle(app, title: "Tyfloświat 4/2025", route: "title-magazine-fallback")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "magazine.issues.list").firstMatch.exists)
	}

	func testSingleArticleTitleLoadingAndBack() {
		let app = titleApp(["UI_TESTING_STALL_DETAIL_REQUESTS"])
		tapTitleRow(app, "article.row.2")
		XCTAssertTrue(app.progressIndicators.firstMatch.waitForExistence(timeout: limitUI))
		let traits = saveTitleEvidence(app, route: "title-loading")
		checkArticleHeader(app, title: "Test artykuł", route: "title-loading", traits: traits)
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "news.list").firstMatch.exists)
		tapTitleRow(app, "article.row.2")
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-after-loading-back")
	}

	func testSingleArticleTitleRetry() {
		let app = titleApp(["UI_TESTING_TITLE_DETAIL_ERROR"])
		tapTitleRow(app, "article.row.2")
		let retry = app.buttons["postDetail.retry"]
		XCTAssertTrue(retry.waitForExistence(timeout: limitUI))
		let traits = saveTitleEvidence(app, route: "title-error")
		checkArticleHeader(app, title: "Test artykuł", route: "title-error", traits: traits)
		retry.tap()
		checkSingleArticleTitle(app, title: "Test artykuł", route: "title-after-retry")
		tapBackButton(in: app)
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "news.list").firstMatch.exists)
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

	private func checkContentTime(_ app: XCUIApplication, id: String, time: String, screen: String) -> XCUIElement {
		let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
		XCTAssertTrue(row.waitForExistence(timeout: limitUI))
		let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", time), object: row)
		XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: limitUI), .completed)
		XCTAssertEqual(row.label.components(separatedBy: time).count, 2, "Czas dokładnie raz w nazwie wiersza")
		let label = XCTAttachment(string: "\(screen): \(row.label)\nvalue: \(String(describing: row.value))")
		label.name = "czas-\(screen)-etykieta"
		label.lifetime = .keepAlways
		add(label)
		let image = XCTAttachment(screenshot: app.screenshot())
		image.name = "czas-\(screen)"
		image.lifetime = .keepAlways
		add(image)
		return row
	}

	/// Ten sam proces i ekran, zmiana serwera jawnie PRZED pojedynczym gestem.
	private func exerciseTimeRefresh(_ app: XCUIApplication, rows: [(String, Bool)], listID: String, screen: String) {
		let server = app.buttons["timeTest.server"]
		XCTAssertTrue(server.waitForExistence(timeout: limitUI))
		let process = server.label.components(separatedBy: "proces: ").last!
		for (id, _) in rows {
			_ = checkContentTime(app, id: id, time: "Czas niedostępny", screen: screen + "-missing")
		}
		// Identyfikator bywa dziedziczony przez ukryte tło SwiftUI. Gest
		// kierujemy do rzeczywistego kontenera przewijania, nie pierwszego .any.
		let containers = [app.scrollViews.matching(identifier: listID).firstMatch,
		                  app.collectionViews.matching(identifier: listID).firstMatch,
		                  app.tables.matching(identifier: listID).firstMatch]
		let target = containers.first { $0.exists && $0.frame.height > 100 && $0.frame.minY.isFinite }
		XCTAssertNotNil(target, "Rzeczywisty kontener listy \(listID)")
		guard let list = target else { return }
		let container = XCTAttachment(string: list.debugDescription)
		container.name = "\(screen)-scroll-container"; container.lifetime = .keepAlways; add(container)
		for stage in 1 ... 4 {
			let before = rows.map { app.descendants(matching: .any).matching(identifier: $0.0).firstMatch.label }
			server.tap()
			XCTAssertTrue(server.label.contains("Serwer: \(stage),"))
			XCTAssertTrue(server.label.hasSuffix(process))
			// Sama kontrola serwera nie zmienia danych wierszy.
			XCTAssertEqual(rows.map { app.descendants(matching: .any).matching(identifier: $0.0).firstMatch.label }, before)
			let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
			let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
			start.press(forDuration: 0.05, thenDragTo: end)
			for (id, audio) in rows {
				let time = stage == 1 ? (audio ? "Czas trwania: 1 godzina 23 minuty 4 sekundy" : "Czytanie: około 6 minut")
					: stage == 2 ? (audio ? "Czas trwania: 1 minuta" : "Czytanie: około 7 minut") : "Czas niedostępny"
				_ = checkContentTime(app, id: id, time: time, screen: "\(screen)-stage\(stage)")
			}
			if stage == 2 {
				let unchanged = rows.map { app.descendants(matching: .any).matching(identifier: $0.0).firstMatch.label }
				start.press(forDuration: 0.05, thenDragTo: end)
				XCTAssertEqual(rows.map { app.descendants(matching: .any).matching(identifier: $0.0).firstMatch.label }, unchanged)
				let attachment = XCTAttachment(string: unchanged.joined(separator: "\n"))
				attachment.name = "\(screen)-unchanged"; attachment.lifetime = .keepAlways; add(attachment)
			}
		}
		server.tap() // missing dla następnej listy, bez restartu aplikacji
		XCTAssertTrue(server.label.contains("Serwer: 0,"))
		XCTAssertTrue(server.label.hasSuffix(process))
	}

	private func samplePlayback(_ app: XCUIApplication, screen: String) -> [String: String] {
		let sample = app.buttons["timeTest.sample"]
		sample.tap()
		let text = sample.value as? String ?? ""
		let attachment = XCTAttachment(string: text)
		attachment.name = screen; attachment.lifetime = .keepAlways; add(attachment)
		let values = Dictionary(uniqueKeysWithValues: text.split(separator: ";").compactMap { part -> (String, String)? in
			let pair = part.split(separator: "=", maxSplits: 1)
			return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
		})
		XCTAssertEqual(values["playing"], "true")
		XCTAssertEqual(values["changes"], "0")
		XCTAssertEqual(values["interruptions"], "0")
		XCTAssertEqual(values["regressions"], "0")
		return values
	}

	private func startMeasuredAudio(_ app: XCUIApplication) -> [String: String] {
		app.buttons["timeTest.audio"].tap()
		let playing = app.staticTexts["timeTest.playing"]
		let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Gra"), object: playing)
		XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: limitUI), .completed)
		app.buttons["timeTest.measure"].tap()
		return samplePlayback(app, screen: "audio-before")
	}

	private func comparePlayback(_ before: [String: String], _ after: [String: String]) {
		XCTAssertEqual(before["item"], after["item"])
		XCTAssertGreaterThan(Double(after["time"] ?? "") ?? -1, (Double(before["time"] ?? "") ?? 0) + 1)
		XCTAssertGreaterThan(Int(after["ticks"] ?? "") ?? 0, 4)
	}

	func testTimeRefreshWhileRealAudioContinues() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH", "UI_TESTING_TIME_PLAYBACK"])
		app.launch()
		let before = startMeasuredAudio(app)
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true), ("article.row.2", false)], listID: "news.list", screen: "audio-news")
		comparePlayback(before, samplePlayback(app, screen: "audio-after-gestures"))
	}

	func testTimeResumePreservesScrolledPositionActionsAndAudio() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH", "UI_TESTING_TIME_PLAYBACK", "UI_TESTING_TIME_LONG_LIST"])
		app.launch()
		let before = startMeasuredAudio(app)
		let list = app.scrollViews["news.list"]
		let row = app.descendants(matching: .any).matching(identifier: "podcast.row.140").firstMatch
		// Krótkie przeciągnięcie z przytrzymaniem końca nie wykonuje flicka.
		// Szybkie swipeUp na iOS26.5 przeskakiwało wiersz140 aż do końca listy.
		for _ in 0 ..< 12 {
			if row.exists, row.isHittable, row.frame.midY > 150, row.frame.midY < 650 { break }
			let targetAbove = row.exists && row.frame.midY.isFinite && row.frame.midY < 150
			let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
			let end = start.withOffset(CGVector(dx: 0, dy: targetAbove ? 140 : -140))
			start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
		}
		XCTAssertTrue(row.isHittable)
		let frame = row.frame
		XCTAssertGreaterThan(frame.minY, 80)
		XCTAssertLessThan(frame.maxY, app.frame.maxY - 100)
		_ = checkContentTime(app, id: "podcast.row.140", time: "Czas niedostępny", screen: "scrolled-before")
		let server = app.buttons["timeTest.server"]
		let process = server.label.components(separatedBy: "proces: ").last!
		server.tap()
		XCUIDevice.shared.press(.home)
		Thread.sleep(forTimeInterval: 121)
		app.activate()
		XCTAssertTrue(server.label.hasSuffix(process))
		_ = checkContentTime(app, id: "podcast.row.140", time: "Czas trwania: 1 godzina 23 minuty 4 sekundy", screen: "scrolled-after")
		XCTAssertEqual(row.frame.minY, frame.minY, accuracy: 2)
		let geometry = XCTAttachment(string: "before=\(frame);after=\(row.frame)")
		geometry.name = "scrolled-geometry"; geometry.lifetime = .keepAlways; add(geometry)
		comparePlayback(before, samplePlayback(app, screen: "audio-after-scrolled-resume"))
		row.press(forDuration: 1)
		let addFavorite = app.buttons["Dodaj do ulubionych"].firstMatch
		XCTAssertTrue(addFavorite.waitForExistence(timeout: limitUI)); addFavorite.tap()
		row.press(forDuration: 1)
		let removeFavorite = app.buttons["Usuń z ulubionych"].firstMatch
		XCTAssertTrue(removeFavorite.waitForExistence(timeout: limitUI)); removeFavorite.tap()
		XCTAssertTrue(row.isHittable)
		row.tap()
		let favorite = app.descendants(matching: .any).matching(identifier: "podcastDetail.favorite").firstMatch
		XCTAssertTrue(favorite.waitForExistence(timeout: limitUI)); favorite.tap()
		comparePlayback(before, samplePlayback(app, screen: "audio-after-row-actions"))
	}

	func testTimeRefreshOldFavoritesSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		openFavoritesFromMenu(in: app)
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true), ("article.row.2", false), ("article.row.400", false)], listID: "favorites.list", screen: "favorites")
	}

	func testTimeRefreshNewsSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true), ("article.row.2", false)], listID: "news.list", screen: "news")
	}

	func testTimeRefreshAllPodcastsSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Podcasty"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "podcastCategories.all").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true)], listID: "allPodcasts.list", screen: "all-podcasts")
	}

	func testTimeRefreshPodcastCategorySameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Podcasty"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true)], listID: "categoryPodcasts.list", screen: "category-podcasts")
	}

	func testTimeRefreshAllArticlesSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "articleCategories.all").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeRefresh(app, rows: [("podcast.row.2", false)], listID: "allArticles.list", screen: "all-articles")
	}

	func testTimeRefreshArticleCategorySameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeRefresh(app, rows: [("podcast.row.2", false)], listID: "categoryArticles.list", screen: "category-articles")
	}

	func testTimeRefreshSearchSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Szukaj"].tap()
		let field = app.textFields["search.field"]
		XCTAssertTrue(field.waitForExistence(timeout: limitUI)); field.tap(); field.typeText("test")
		app.buttons["search.button"].tap()
		exerciseTimeRefresh(app, rows: [("podcast.row.1", true), ("article.row.2", false)], listID: "search.list", screen: "search")
	}

	func testTimeRefreshMagazinePagesSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let magazine = app.descendants(matching: .any).matching(identifier: "articleCategories.magazine").firstMatch
		XCTAssertTrue(magazine.waitForExistence(timeout: limitUI)); magazine.tap()
		let year = app.descendants(matching: .any).matching(identifier: "magazine.year.2025").firstMatch
		XCTAssertTrue(year.waitForExistence(timeout: limitUI)); year.tap()
		let issue = app.descendants(matching: .any).matching(identifier: "magazine.issue.7772").firstMatch
		XCTAssertTrue(issue.waitForExistence(timeout: limitUI)); issue.tap()
		exerciseTimeRefresh(app, rows: [("magazine.article.7774", false)], listID: "magazine.toc.list", screen: "magazine-pages")
	}

	private func exerciseTimeResume(_ app: XCUIApplication, rows: [(String, Bool)], screen: String) {
		let server = app.buttons["timeTest.server"]
		XCTAssertTrue(server.waitForExistence(timeout: limitUI))
		let process = server.label.components(separatedBy: "proces: ").last!
		for (id, _) in rows {
			_ = checkContentTime(app, id: id, time: "Czas niedostępny", screen: screen + "-start")
		}
		server.tap()
		XCUIDevice.shared.press(.home)
		app.activate()
		for (id, _) in rows {
			_ = checkContentTime(app, id: id, time: "Czas niedostępny", screen: screen + "-early")
		}
		XCUIDevice.shared.press(.home)
		// Realny próg produkcyjny. Nie zmieniamy zegara ani polityki aplikacji.
		Thread.sleep(forTimeInterval: 121)
		app.activate()
		XCTAssertTrue(server.label.hasSuffix(process), "Wznowienie, nie nowy proces")
		for (id, audio) in rows {
			_ = checkContentTime(app, id: id, time: audio ? "Czas trwania: 1 godzina 23 minuty 4 sekundy" : "Czytanie: około 6 minut", screen: screen + "-resumed")
		}
	}

	func testTimeResumeNewsWithoutNewIDs() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		exerciseTimeResume(app, rows: [("podcast.row.1", true), ("article.row.2", false)], screen: "resume-news")
	}

	func testTimeResumeAllPodcastsSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Podcasty"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "podcastCategories.all").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeResume(app, rows: [("podcast.row.1", true)], screen: "resume-all-podcasts")
	}

	func testTimeResumePodcastCategorySameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Podcasty"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeResume(app, rows: [("podcast.row.1", true)], screen: "resume-category-podcasts")
	}

	func testTimeResumeAllArticlesSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "articleCategories.all").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeResume(app, rows: [("podcast.row.2", false)], screen: "resume-all-articles")
	}

	func testTimeResumeArticleCategorySameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let link = app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch
		XCTAssertTrue(link.waitForExistence(timeout: limitUI)); link.tap()
		exerciseTimeResume(app, rows: [("podcast.row.2", false)], screen: "resume-category-articles")
	}

	func testTimeResumeSearchSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Szukaj"].tap()
		let field = app.textFields["search.field"]
		XCTAssertTrue(field.waitForExistence(timeout: limitUI)); field.tap(); field.typeText("test")
		app.buttons["search.button"].tap()
		exerciseTimeResume(app, rows: [("podcast.row.1", true), ("article.row.2", false)], screen: "resume-search")
	}

	func testTimeResumeMagazinePagesSameProcess() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		app.tabBars.buttons["Artykuły"].tap()
		let magazine = app.descendants(matching: .any).matching(identifier: "articleCategories.magazine").firstMatch
		XCTAssertTrue(magazine.waitForExistence(timeout: limitUI)); magazine.tap()
		let year = app.descendants(matching: .any).matching(identifier: "magazine.year.2025").firstMatch
		XCTAssertTrue(year.waitForExistence(timeout: limitUI)); year.tap()
		let issue = app.descendants(matching: .any).matching(identifier: "magazine.issue.7772").firstMatch
		XCTAssertTrue(issue.waitForExistence(timeout: limitUI)); issue.tap()
		exerciseTimeResume(app, rows: [("magazine.article.7774", false)], screen: "resume-magazine-pages")
	}

	func testTimeResumeFavoritesWithoutRecreation() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_TIME_REFRESH"])
		app.launch()
		openFavoritesFromMenu(in: app)
		exerciseTimeResume(app, rows: [("podcast.row.1", true), ("article.row.2", false), ("article.row.400", false)], screen: "resume-favorites")
	}

	func testContentTimesAcrossAllLists() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES"])
		app.launch()
		let audio = "Czas trwania: 1 godzina 23 minuty 4 sekundy"
		let reading = "Czytanie: około 6 minut"
		_ = checkContentTime(app, id: "article.row.2", time: reading, screen: "nowosci-artykul")
		let podcast = checkContentTime(app, id: "podcast.row.1", time: audio, screen: "nowosci-podcast")
		podcast.tap()
		let favorite = app.descendants(matching: .any).matching(identifier: "podcastDetail.favorite").firstMatch
		XCTAssertTrue(favorite.waitForExistence(timeout: limitUI))
		favorite.tap()
		openFavoritesFromMenu(in: app)
		_ = checkContentTime(app, id: "podcast.row.1", time: audio, screen: "ulubione-podcast")
		tapBackButton(in: app)
		let article = checkContentTime(app, id: "article.row.2", time: reading, screen: "nowosci-po-powrocie")
		article.press(forDuration: 1)
		let addButton = app.buttons["Dodaj do ulubionych"].firstMatch
		if addButton.waitForExistence(timeout: 2) { addButton.tap() }
		else { app.menuItems["Dodaj do ulubionych"].firstMatch.tap() }
		openFavoritesFromMenu(in: app)
		_ = checkContentTime(app, id: "article.row.2", time: reading, screen: "ulubione-artykul")
		tapBackButton(in: app)

		app.tabBars.buttons["Podcasty"].tap()
		let allPodcasts = app.descendants(matching: .any).matching(identifier: "podcastCategories.all").firstMatch
		XCTAssertTrue(allPodcasts.waitForExistence(timeout: limitUI)); allPodcasts.tap()
		_ = checkContentTime(app, id: "podcast.row.1", time: audio, screen: "wszystkie-podcasty")
		tapBackButton(in: app)
		app.descendants(matching: .any).matching(identifier: "category.row.10").firstMatch.tap()
		_ = checkContentTime(app, id: "podcast.row.1", time: audio, screen: "kategoria-podcastow")
		tapBackButton(in: app)

		app.tabBars.buttons["Artykuły"].tap()
		let allArticles = app.descendants(matching: .any).matching(identifier: "articleCategories.all").firstMatch
		XCTAssertTrue(allArticles.waitForExistence(timeout: limitUI)); allArticles.tap()
		_ = checkContentTime(app, id: "podcast.row.2", time: reading, screen: "wszystkie-artykuly")
		tapBackButton(in: app)
		app.descendants(matching: .any).matching(identifier: "category.row.20").firstMatch.tap()
		_ = checkContentTime(app, id: "podcast.row.2", time: reading, screen: "kategoria-artykulow")
		tapBackButton(in: app)
		app.descendants(matching: .any).matching(identifier: "articleCategories.magazine").firstMatch.tap()
		let year = app.descendants(matching: .any).matching(identifier: "magazine.year.2025").firstMatch
		XCTAssertTrue(year.waitForExistence(timeout: limitUI)); year.tap()
		let issue = app.descendants(matching: .any).matching(identifier: "magazine.issue.7772").firstMatch
		XCTAssertTrue(issue.waitForExistence(timeout: limitUI))
		XCTAssertFalse(issue.label.contains("Czytanie:"))
		XCTAssertFalse(issue.label.contains("Czas niedostępny"))
		issue.tap()
		_ = checkContentTime(app, id: "magazine.article.7774", time: reading, screen: "artykul-numeru")

		app.tabBars.buttons["Szukaj"].tap()
		let field = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
		XCTAssertTrue(field.waitForExistence(timeout: limitUI)); field.tap(); field.typeText("Test")
		app.descendants(matching: .any).matching(identifier: "search.button").firstMatch.tap()
		_ = checkContentTime(app, id: "article.row.2", time: reading, screen: "szukaj-artykul")
		_ = checkContentTime(app, id: "podcast.row.1", time: audio, screen: "szukaj-podcast")
	}

	func testMetadataOutageKeepsRealArticleAndPlaybackReachable() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_CONTENT_TIMES", "UI_TESTING_METADATA_FAILURE"])
		app.launch()
		let article = checkContentTime(app, id: "article.row.2", time: "Czas niedostępny", screen: "awaria-lista")
		article.tap()
		let paragraph = app.webViews.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Kontrolny akapit artykułu Tyfloświata.")).firstMatch
		XCTAssertTrue(paragraph.waitForExistence(timeout: limitUI))
		let text = XCTAttachment(string: paragraph.label)
		text.name = "awaria-rzeczywisty-akapit-WebKit"; text.lifetime = .keepAlways; add(text)
		let image = XCTAttachment(screenshot: app.screenshot())
		image.name = "awaria-artykul-WebKit"; image.lifetime = .keepAlways; add(image)
		tapBackButton(in: app)
		let podcast = checkContentTime(app, id: "podcast.row.1", time: "Czas niedostępny", screen: "awaria-podcast")
		podcast.tap()
		let listen = app.descendants(matching: .any).matching(identifier: "podcastDetail.listen").firstMatch
		XCTAssertTrue(listen.waitForExistence(timeout: limitUI))
		listen.tap()
		XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "player.playPause").firstMatch.waitForExistence(timeout: limitUI))
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

	func testArticleRecoveryAutoRecoversAfterControlledSingleRenderFailure() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_SAFE_HTML_FAIL_ONCE"])
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let content = app.descendants(matching: .any).matching(identifier: "articleDetail.content").firstMatch
		XCTAssertTrue(content.waitForExistence(timeout: limitUI))

		let paragraph = app.webViews.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Kontrolny akapit artykułu Tyfloświata.")).firstMatch
		XCTAssertTrue(paragraph.waitForExistence(timeout: limitUI))

		let retryButton = app.buttons["articleDetail.retry"]
		XCTAssertFalse(retryButton.exists)

		let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		screenshot.name = "SAFEHTML-FAIL-ONCE-RECOVERED"
		screenshot.lifetime = .keepAlways
		add(screenshot)
	}

	func testArticleRecoveryRequiresManualRetryAfterControlledDoubleRenderFailure() {
		let app = makeApp(additionalLaunchArguments: ["UI_TESTING_SAFE_HTML_FAIL_TWICE"])
		app.launch()

		app.tabBars.buttons["Nowości"].tap()

		let articleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(articleRow.waitForExistence(timeout: limitUI))
		articleRow.tap()

		let retryButton = app.buttons["articleDetail.retry"]
		XCTAssertTrue(retryButton.waitForExistence(timeout: limitUI))

		let failureScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		failureScreenshot.name = "SAFEHTML-FAIL-TWICE-BEFORE-RETRY"
		failureScreenshot.lifetime = .keepAlways
		add(failureScreenshot)

		retryButton.tap()

		let paragraph = app.webViews.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Kontrolny akapit artykułu Tyfloświata.")).firstMatch
		XCTAssertTrue(paragraph.waitForExistence(timeout: limitUI))

		let successScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		successScreenshot.name = "SAFEHTML-FAIL-TWICE-RECOVERED"
		successScreenshot.lifetime = .keepAlways
		add(successScreenshot)
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
		XCTAssertEqual(podcastRow.label, "Podcast. Test podcast. Czas niedostępny")
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
		XCTAssertEqual(initialRow.label, "Podcast. Test podcast. Czas niedostępny")

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

		let expectedLabel = "Test podcast. Podcast. Czas niedostępny"
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
		XCTAssertEqual(articleRow.label, "Artykuł. Test artykuł. Czas niedostępny")
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
		XCTAssertEqual(initialNewsRow.label, "Podcast. Test podcast. Czas niedostępny")

		let initialArticleRow = app.descendants(matching: .any).matching(identifier: "article.row.2").firstMatch
		XCTAssertTrue(initialArticleRow.waitForExistence(timeout: limitUI))
		XCTAssertEqual(initialArticleRow.label, "Artykuł. Test artykuł. Czas niedostępny")

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
		XCTAssertEqual(refreshedCategoryPodcast.label, "Test podcast w kategorii 2. Czas niedostępny")

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
		XCTAssertEqual(refreshedCategoryArticle.label, "Test artykuł 2. Czas niedostępny")
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
