//
//  ZrzutyPrzyciskow.swift
//  TyflocentrumUITests
//
//  Zrzuty ekranu odtwarzacza i szczegółów audycji — do WERYFIKACJI WZROKOWEJ
//  czytelności przycisków (prędkość, znaczniki czasu, odnośniki, ulubione).
//
//  PO CO OSOBNO OD ZrzutyEkranu.swift: tamten plik robi materiał marketingowy
//  do karty App Store (ładne ekrany główne). Ten robi materiał DOWODOWY: ma
//  pokazać konkretne przyciski w powiększeniu, żeby dało się ocenić, czy są
//  widoczne dla osoby korzystającej z powiększenia i zwiększonego kontrastu.
//  Zlepienie obu w jeden plik dałoby zrzuty, które nie służą dobrze żadnemu
//  z tych celów.
//
//  Zrzuty robimy w DWÓCH wariantach ustawień dostępności, bo problem zgłoszono
//  właśnie dla trybu zwiększonego kontrastu:
//    - domyślnym,
//    - z Bold Text + Increase Contrast + Button Shapes.
//  Symulator przyjmuje te ustawienia przez `simctl ui`, więc nie trzeba klikać.

import XCTest

final class ZrzutyPrzyciskow: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	private var etykietaUrzadzenia: String {
		ProcessInfo.processInfo.environment["ETYKIETA_URZADZENIA"] ?? "urzadzenie"
	}

	private var etykietaWariantu: String {
		ProcessInfo.processInfo.environment["ETYKIETA_WARIANTU"] ?? "domyslny"
	}

	private func zapisz(_ app: XCUIApplication, _ nazwa: String) {
		let zalacznik = XCTAttachment(screenshot: app.screenshot())
		zalacznik.name = "\(etykietaUrzadzenia)-\(etykietaWariantu)-\(nazwa)"
		// Bez .keepAlways XCTest kasuje załączniki testów, które przeszły.
		zalacznik.lifetime = .keepAlways
		add(zalacznik)
	}

	/// Otwiera pierwszy podcast z listy i dochodzi do odtwarzacza.
	func testZrzutyPrzyciskowOdtwarzacza() {
		let app = XCUIApplication()
		app.launchArguments = ["UI_TESTING", "UI_TESTING_SCREENSHOTS"]
		app.launch()

		let listaNowosci = app.descendants(matching: .any)
			.matching(identifier: "news.list").firstMatch
		XCTAssertTrue(listaNowosci.waitForExistence(timeout: 30),
		              "Nie wstala lista Nowosci.")
		Thread.sleep(forTimeInterval: 2)

		// Szczegóły audycji: tu jest przycisk „Dodaj do ulubionych”.
		let pierwszyWiersz = app.descendants(matching: .any)
			.matching(identifier: "podcast.row.1").firstMatch
		guard pierwszyWiersz.waitForExistence(timeout: 15) else {
			XCTContext.runActivity(named: "Brak wiersza podcastu - pomijam") { _ in }
			return
		}
		pierwszyWiersz.tap()
		Thread.sleep(forTimeInterval: 3)
		zapisz(app, "1-szczegoly-audycji")

		// Odtwarzacz: prędkość, znaczniki czasu, odnośniki.
		let odtworz = app.descendants(matching: .any)
			.matching(identifier: "podcastDetail.listen").firstMatch
		if odtworz.waitForExistence(timeout: 10) {
			odtworz.tap()
			Thread.sleep(forTimeInterval: 4)
			zapisz(app, "2-odtwarzacz")
		} else {
			XCTContext.runActivity(named: "Brak przycisku odtwarzania") { _ in }
		}
	}
}
