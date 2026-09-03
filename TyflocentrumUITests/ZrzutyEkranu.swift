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
//  DLACZEGO TAKŻE UI_TESTING_SCREENSHOTS. Sam UI_TESTING daje tytuły w stylu
//  „Test podcast”, „Test artykuł” — zmierzone na pierwszym przebiegu i widoczne
//  na zrzutach, więc do sklepu się nie nadawały. Te napisy są jednak
//  KONTRAKTEM 13 asercji w testach, więc nie wolno ich zmienić globalnie.
//  Druga flaga podmienia je na realistyczne tylko tutaj. Szczegóły i test
//  kolejności podmiany: tools/test_tytuly_zrzutow.py.

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

	/// Znajduje zakładkę niezależnie od tego, jak system ją wyrenderował.
	///
	/// ZMIERZONE (run 33782945660): na iPhonie `app.tabBars.buttons["Podcasty"]`
	/// działa, ale na iPadzie Pro 13" z iOS 26 zwraca element nieistniejący —
	/// zrzuty kończyły się po pierwszym ekranie i z iPada mieliśmy 1 zrzut
	/// zamiast 5. Przyczyna nie jest w naszym kodzie (`ContentView` to jeden
	/// `TabView` dla obu urządzeń): na iPadzie system renderuje `TabView` jako
	/// górny pasek albo panel boczny, a nie dolny `tabBar`, więc kolekcja
	/// `tabBars` jest pusta.
	///
	/// Dlatego szukamy po kolei w trzech miejscach zamiast zakładać jedno.
	private func zakladka(_ nazwa: String, w app: XCUIApplication) -> XCUIElement {
		let wTabBarze = app.tabBars.buttons[nazwa]
		if wTabBarze.exists { return wTabBarze }
		let wPanelu = app.buttons[nazwa]
		if wPanelu.exists { return wPanelu }
		// Ostatnia próba: dowolny element o tej etykiecie, na który da się kliknąć.
		return app.descendants(matching: .any).matching(identifier: nazwa).firstMatch
	}

	private func przejdzDoZakladki(_ nazwa: String, w app: XCUIApplication,
	                               zrzut: String)
	{
		let element = zakladka(nazwa, w: app)
		guard element.waitForExistence(timeout: 15) else {
			// Brak zakładki nie może przerwać całych zrzutów: lepiej mieć cztery
			// ekrany i wiedzieć, którego brakuje, niż jeden i błąd.
			XCTContext.runActivity(named: "Brak zakladki \(nazwa) - pomijam") { _ in }
			return
		}
		element.tap()
		Thread.sleep(forTimeInterval: 2)
		zapisz(app, zrzut)
	}

	func testZrzutyDoKartySklepu() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING", "UI_TESTING_SCREENSHOTS"]
		app.launch()

		// 1. Nowości - ekran startowy, najważniejszy zrzut.
		let listaNowosci = app.descendants(matching: .any)
			.matching(identifier: "news.list").firstMatch
		XCTAssertTrue(listaNowosci.waitForExistence(timeout: 30),
		              "Nie wstala lista Nowosci - zrzuty bylyby puste.")
		// Chwila na dociągnięcie i ułożenie treści; bez tego łapiemy szkielet
		// widoku zamiast zawartości.
		Thread.sleep(forTimeInterval: 3)
		zapisz(app, "1-nowosci")

		przejdzDoZakladki("Podcasty", w: app, zrzut: "2-podcasty")
		przejdzDoZakladki("Tyfloradio", w: app, zrzut: "3-tyfloradio")
		przejdzDoZakladki("Artykuły", w: app, zrzut: "4-artykuly")
		przejdzDoZakladki("Szukaj", w: app, zrzut: "5-szukaj")
	}
}
