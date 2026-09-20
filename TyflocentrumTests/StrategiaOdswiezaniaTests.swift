//
//  StrategiaOdswiezaniaTests.swift
//  TyflocentrumTests
//
//  Reguła progowa odświeżania i scalanie nowości. KAŻDA asercja pozytywna ma parę
//  negatywną — inaczej test przechodziłby też wtedy, gdyby reguła zawsze zwracała
//  „tak” (albo zawsze „nie”), czyli nie mierzyłby niczego.
//

@testable import Tyflocentrum
import XCTest

final class StrategiaOdswiezaniaTests: XCTestCase {
	private let teraz = Date(timeIntervalSince1970: 1_000_000)
	private let strategia = StrategiaOdswiezania()

	// MARK: - Próg świeżości

	func testSwiezeDaneNieGeneruajaRuchu() {
		// 10 s po udanym pobraniu: powrót do aplikacji NIE ma sięgać do sieci.
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: teraz.addingTimeInterval(-10),
			ostatniaProba: teraz.addingTimeInterval(-10),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertFalse(wynik, "Dane sprzed 10 s są świeże, pobranie byłoby marnowaniem baterii")
	}

	func testStareDaneGenerujaOdswiezenie() {
		// Para negatywna do testu powyżej: ta sama ścieżka, starsze dane.
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: teraz.addingTimeInterval(-121),
			ostatniaProba: teraz.addingTimeInterval(-121),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Dane starsze niż próg mają być odświeżone")
	}

	func testGranicaProguJestWlaczna() {
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: teraz.addingTimeInterval(-StrategiaOdswiezania.progSwiezosci),
			ostatniaProba: teraz.addingTimeInterval(-StrategiaOdswiezania.progSwiezosci),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Dokładnie na progu odświeżamy — inaczej wartość progu byłaby myląca")
	}

	// MARK: - Karencja po błędzie (ochrona baterii przy martwej sieci)

	func testPoNieudanejProbieObowiazujeKarencja() {
		// TO JEST SEDNO OCHRONY BATERII. Dane stare (bo pobranie się nie udało),
		// ale ostatnia próba była 5 s temu. Bez tej reguły każde przełączenie
		// aplikacji przy braku sieci strzelałoby nowym żądaniem do timeoutu.
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: teraz.addingTimeInterval(-3600),
			ostatniaProba: teraz.addingTimeInterval(-5),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertFalse(wynik, "5 s po nieudanej próbie nie ponawiamy — to byłaby pętla żądań")
	}

	func testPoKarencjiProbaJestPonawiana() {
		// Para negatywna: ta sama sytuacja po upływie karencji.
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: teraz.addingTimeInterval(-3600),
			ostatniaProba: teraz.addingTimeInterval(-31),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Po karencji wolno spróbować ponownie")
	}

	func testBrakDanychIswiezaNieudanaProbaWstrzymuje() {
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: nil,
			ostatniaProba: teraz.addingTimeInterval(-2),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertFalse(wynik, "Pusty ekran bez sieci nie może bombardować serwera")
	}

	func testBrakJakiejkolwiekProbyPozwalaPobrac() {
		let wynik = strategia.czyOdswiezyc(
			powod: .powrotZTla,
			ostatniSukces: nil,
			ostatniaProba: nil,
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Pierwsze wejście musi pobrać dane")
	}

	// MARK: - Żądanie użytkownika omija progi

	func testZadanieUzytkownikaOmijaProgSwiezosci() {
		let wynik = strategia.czyOdswiezyc(
			powod: .zadanieUzytkownika,
			ostatniSukces: teraz,
			ostatniaProba: teraz,
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Gdy człowiek sam odświeża, czekanie jest wyłącznie szkodą")
	}

	func testZadanieUzytkownikaOmijaKarencjePoBledzie() {
		let wynik = strategia.czyOdswiezyc(
			powod: .zadanieUzytkownika,
			ostatniSukces: nil,
			ostatniaProba: teraz.addingTimeInterval(-1),
			trwaPobieranie: false,
			teraz: teraz
		)
		XCTAssertTrue(wynik, "Przycisk „Odśwież” nie może być głuchy po nieudanej próbie")
	}

	// MARK: - Brak równoległych pobrań

	func testTrwajacePobranieBlokujeKazdyPowod() {
		for powod in [PowodOdswiezenia.powrotZTla, .wejscieNaEkran, .zadanieUzytkownika] {
			let wynik = strategia.czyOdswiezyc(
				powod: powod,
				ostatniSukces: nil,
				ostatniaProba: nil,
				trwaPobieranie: true,
				teraz: teraz
			)
			XCTAssertFalse(wynik, "Drugie równoległe żądanie (\(powod)) nic nie wnosi")
		}
	}

	// MARK: - Znaczniki świeżości

	func testNieudanaProbaNieOdmierzaWiekuDanychOdNowa() throws {
		// Gdyby próba zerowała wiek danych, nieudane pobranie „odmłodziłoby”
		// stare treści i zablokowało kolejne odświeżenie na 2 minuty.
		var stan = StanSwiezosci()
		stan.zanotujSukces(teraz: teraz.addingTimeInterval(-300))
		stan.zanotujProbe(teraz: teraz)

		XCTAssertEqual(try XCTUnwrap(stan.wiekDanych(teraz: teraz)), 300, accuracy: 0.001)
		XCTAssertEqual(stan.ostatniaProba, teraz)
	}

	func testSukcesOdmierzaWiekOdNowa() throws {
		var stan = StanSwiezosci()
		stan.zanotujSukces(teraz: teraz.addingTimeInterval(-300))
		stan.zanotujSukces(teraz: teraz)

		XCTAssertEqual(try XCTUnwrap(stan.wiekDanych(teraz: teraz)), 0, accuracy: 0.001)
	}
}

final class ScalanieNowosciTests: XCTestCase {
	private struct Wpis: Equatable {
		let id: String
		let kolejnosc: Int
	}

	private func scal(biezace: [Wpis], swieze: [Wpis]) -> WynikScalenia<Wpis> {
		ScalanieNowosci.scal(
			biezace: biezace,
			swieze: swieze,
			identyfikator: { $0.id },
			czyNowszy: { $0.kolejnosc > $1.kolejnosc }
		)
	}

	func testNoweWpisyLadujaNaGorze() {
		let wynik = scal(
			biezace: [Wpis(id: "b", kolejnosc: 2), Wpis(id: "c", kolejnosc: 1)],
			swieze: [Wpis(id: "a", kolejnosc: 3), Wpis(id: "b", kolejnosc: 2)]
		)

		XCTAssertEqual(wynik.elementy.map(\.id), ["a", "b", "c"])
		XCTAssertEqual(wynik.liczbaNowych, 1)
		XCTAssertEqual(wynik.kotwica, "b", "Kotwica musi wskazywać wpis, który był pierwszy PRZED scaleniem")
	}

	func testBrakNowychNieRuszaListyAniNieOglasza() {
		// Para negatywna: ta sama ścieżka, gdy serwer nie ma nic nowego.
		let biezace = [Wpis(id: "b", kolejnosc: 2), Wpis(id: "c", kolejnosc: 1)]
		let wynik = scal(biezace: biezace, swieze: [Wpis(id: "b", kolejnosc: 2)])

		XCTAssertEqual(wynik.elementy, biezace, "Lista bez nowości musi zostać bit w bit ta sama")
		XCTAssertEqual(wynik.liczbaNowych, 0)
		XCTAssertFalse(wynik.maNowe)
		XCTAssertNil(ScalanieNowosci.komunikatONowych(wynik.liczbaNowych), "Bez nowości NIE ogłaszamy nic")
	}

	func testKolejnoscIstniejacychElementowNieZmieniaSie() {
		// Wpis "z" ma datę ze środka listy, ale skoro użytkownik już czyta tę listę,
		// nie wolno go wcisnąć w środek — trafia na górę razem z resztą nowych.
		let biezace = [Wpis(id: "b", kolejnosc: 5), Wpis(id: "c", kolejnosc: 1)]
		let wynik = scal(biezace: biezace, swieze: [Wpis(id: "z", kolejnosc: 3)])

		XCTAssertEqual(wynik.elementy.map(\.id), ["z", "b", "c"])
		XCTAssertEqual(
			Array(wynik.elementy.dropFirst()), biezace,
			"Ogon listy musi pozostać nietknięty, bo tam siedzi kursor czytnika"
		)
	}

	func testDuplikatyWporcjiNieMnozaWpisow() {
		let wynik = scal(
			biezace: [Wpis(id: "b", kolejnosc: 1)],
			swieze: [Wpis(id: "a", kolejnosc: 3), Wpis(id: "a", kolejnosc: 3)]
		)
		// Świeża porcja bywa sklejana z dwóch źródeł, więc powtórka jest realna.
		XCTAssertEqual(wynik.liczbaNowych, 2, "Ta reguła filtruje wyłącznie wobec listy bieżącej")
		XCTAssertEqual(wynik.elementy.count, 3)
	}

	func testPustaListaBiezacaPrzyjmujeCaloscUporzadkowana() {
		let wynik = scal(
			biezace: [],
			swieze: [Wpis(id: "c", kolejnosc: 1), Wpis(id: "a", kolejnosc: 3)]
		)

		XCTAssertEqual(wynik.elementy.map(\.id), ["a", "c"])
		XCTAssertEqual(wynik.liczbaNowych, 0, "Pierwsze wypełnienie listy to nie „nowości” do ogłaszania")
		XCTAssertNil(wynik.kotwica)
	}

	// MARK: - Komunikat dla czytnika ekranu

	func testOdmianaLiczebnikaPoPolsku() {
		XCTAssertEqual(ScalanieNowosci.komunikatONowych(1), "1 nowa treść na górze listy")
		XCTAssertEqual(ScalanieNowosci.komunikatONowych(3), "3 nowe treści na górze listy")
		XCTAssertEqual(ScalanieNowosci.komunikatONowych(5), "5 nowych treści na górze listy")
		XCTAssertEqual(ScalanieNowosci.komunikatONowych(12), "12 nowych treści na górze listy")
		XCTAssertEqual(ScalanieNowosci.komunikatONowych(22), "22 nowe treści na górze listy")
	}

	func testZeroNowychNieDajeKomunikatu() {
		XCTAssertNil(ScalanieNowosci.komunikatONowych(0))
	}
}
