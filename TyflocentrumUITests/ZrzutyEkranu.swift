//
//  ZrzutyEkranu.swift
//  TyflocentrumUITests
//
//  Zrzuty ekranu do karty App Store, robione na SYMULATORZE.
//
//  PO CO. Apple wymaga zrzutów dla iPhone'a 6.9" oraz — skoro projekt ma
//  TARGETED_DEVICE_FAMILY "1,2" — także dla iPada 13". Michał nie ma iPada,
//  a kupowanie urządzenia po to, żeby zrobić 5 obrazków, byłoby absurdem.
//  Symulator (nie emulator: uruchamia natywny kod na macOS i renderuje UIKit
//  w prawdziwej rozdzielczości urządzenia) daje zrzuty pikselowo dokładne,
//  akceptowane przez App Store Connect.
//
//  DLACZEGO Z ARGUMENTEM UI_TESTING. Aplikacja w tym trybie stubuje sieć
//  (UITestURLProtocol) i używa Core Data w pamięci. Bez tego zrzuty zależałyby
//  od tego, co akurat jest na serwerach Tyflopodcastu w chwili przebiegu —
//  a karta sklepu ma pokazywać spójny, powtarzalny obraz aplikacji, nie
//  przypadkowy stan produkcji. Dodatkowo unika się przypadkowego pokazania
//  treści, do której nie mamy praw w materiałach marketingowych.
//
//  UWAGA NA TREŚĆ ZRZUTU: to materiał marketingowy, nie dowód techniczny.
//  Jeśli stub pokaże "Test artykuł 1", zrzut nie nadaje się do sklepu — trzeba
//  wtedy wzbogacić dane stubu o realistyczne tytuły. Sprawdź zrzuty OKIEM,
//  zanim wyślesz je Apple; test potrafi tylko potwierdzić rozmiar i format.

import XCTest

final class ZrzutyEkranu: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	/// Nazwa urządzenia trafia do nazwy artefaktu, żeby po pobraniu było jasne,
	/// który zrzut jest z iPhone'a, a który z iPada. `xcparse` zapisuje pliki
	/// pod nazwą załącznika, więc nazwa musi być samoopisowa.
	private var etykietaUrzadzenia: String {
		// Ustawiane w workflow przez SIM_LABEL; w Xcode lokalnie bywa puste.
		ProcessInfo.processInfo.environment["ETYKIETA_URZADZENIA"] ?? "urzadzenie"
	}

	private func zapisz(_ app: XCUIApplication, _ nazwa: String) {
		let zrzut = app.screenshot()
		let zalacznik = XCTAttachment(screenshot: zrzut)
		zalacznik.name = "\(etykietaUrzadzenia)-\(nazwa)"
		// .keepAlways: bez tego XCTest usuwa załączniki z udanych testów,
		// czyli dostalibyśmy zrzuty TYLKO gdy test padnie - dokładnie odwrotnie
		// do tego, po co je robimy.
		zalacznik.lifetime = .keepAlways
		add(zalacznik)
	}

	func testZrzutyDoKartySklepu() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING"]
		app.launch()

		// 1. Nowości - ekran startowy, najważniejszy zrzut.
		let listaNowosci = app.descendants(matching: .any)
			.matching(identifier: "news.list").firstMatch
		XCTAssertTrue(listaNowosci.waitForExistence(timeout: 20),
		              "Nie wstala lista Nowosci - zrzuty bylyby puste.")
		// Chwila na dociągnięcie i ułożenie treści; bez tego łapiemy szkielet
		// widoku zamiast zawartości.
		Thread.sleep(forTimeInterval: 2)
		zapisz(app, "1-nowosci")

		// 2. Podcasty (kategorie).
		if app.tabBars.buttons["Podcasty"].waitForExistence(timeout: 10) {
			app.tabBars.buttons["Podcasty"].tap()
			Thread.sleep(forTimeInterval: 2)
			zapisz(app, "2-podcasty")
		}

		// 3. Tyfloradio - odtwarzacz na żywo.
		if app.tabBars.buttons["Tyfloradio"].exists {
			app.tabBars.buttons["Tyfloradio"].tap()
			Thread.sleep(forTimeInterval: 2)
			zapisz(app, "3-tyfloradio")
		}

		// 4. Artykuły.
		if app.tabBars.buttons["Artykuły"].exists {
			app.tabBars.buttons["Artykuły"].tap()
			Thread.sleep(forTimeInterval: 2)
			zapisz(app, "4-artykuly")
		}

		// 5. Szukaj.
		if app.tabBars.buttons["Szukaj"].exists {
			app.tabBars.buttons["Szukaj"].tap()
			Thread.sleep(forTimeInterval: 2)
			zapisz(app, "5-szukaj")
		}
	}
}
