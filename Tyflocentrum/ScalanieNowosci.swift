//
//  ScalanieNowosci.swift
//  Tyflocentrum
//
//  Scalanie świeżo pobranej pierwszej strony z listą, którą użytkownik już czyta.
//

import Foundation

/// Wynik scalenia: nowa lista oraz to, co trzeba ogłosić czytnikowi ekranu.
struct WynikScalenia<Element> {
	let elementy: [Element]
	/// Liczba wpisów, których wcześniej NIE było na liście.
	let liczbaNowych: Int
	/// Identyfikator elementu, który przed scaleniem był pierwszy na liście.
	/// Służy do zakotwiczenia przewijania, żeby treść nie skoczyła pod palcem.
	let kotwica: String?

	var maNowe: Bool { liczbaNowych > 0 }
}

/// Reguły scalania świadomie wydzielone od widoku i od sieci — to jedyne miejsce,
/// w którym decydujemy, co zobaczy osoba czytająca listę czytnikiem ekranu, więc
/// musi dać się sprawdzić testem bez uruchamiania interfejsu.
///
/// ZASADA NADRZĘDNA: nie ruszamy tego, co użytkownik już ma pod palcem.
/// Nowe wpisy trafiają NAD dotychczasowe, a kolejność i tożsamość istniejących
/// elementów pozostaje bez zmian. Dlatego scalanie NIE sortuje całości od nowa:
/// pełne przesortowanie mogłoby wstawić wpis w środek czytanej listy (artykuł
/// datowany wcześniej niż ostatnio wczytane pozycje), co dla czytnika ekranu jest
/// gorsze niż brak nowości — element pod kursorem zmieniłby sąsiedztwo.
enum ScalanieNowosci {
	/// - Parameters:
	///   - biezace: lista, którą użytkownik widzi teraz.
	///   - swieze: świeżo pobrana pierwsza strona (najnowsze najpierw).
	///   - identyfikator: stabilny klucz elementu.
	///   - czyNowszy: czy element A jest nowszy niż B (do porządku wewnątrz
	///     samej porcji nowych wpisów).
	/// - Returns: lista z nowymi wpisami na górze i liczba nowych.
	static func scal<Element>(
		biezace: [Element],
		swieze: [Element],
		identyfikator: (Element) -> String,
		czyNowszy: (Element, Element) -> Bool
	) -> WynikScalenia<Element> {
		let kotwica = biezace.first.map(identyfikator)

		// Pierwsze wejście: nie ma czego scalać ani czego chronić.
		guard !biezace.isEmpty else {
			return WynikScalenia(
				elementy: swieze.sorted(by: czyNowszy),
				liczbaNowych: 0,
				kotwica: nil
			)
		}

		let znaneID = Set(biezace.map(identyfikator))
		let nowe = swieze.filter { !znaneID.contains(identyfikator($0)) }

		guard !nowe.isEmpty else {
			return WynikScalenia(elementy: biezace, liczbaNowych: 0, kotwica: kotwica)
		}

		// Wewnątrz samej porcji nowych trzymamy porządek malejąco po dacie, żeby
		// najnowszy wpis był pierwszy — ale nie dotykamy porządku reszty listy.
		let noweUporzadkowane = nowe.sorted(by: czyNowszy)

		return WynikScalenia(
			elementy: noweUporzadkowane + biezace,
			liczbaNowych: noweUporzadkowane.count,
			kotwica: kotwica
		)
	}

	/// Komunikat dla czytnika ekranu, z polską odmianą liczebnika.
	///
	/// Osobna funkcja, bo tekst ogłoszenia jest częścią dostępności, a nie
	/// kosmetyką: „Nowe treści: 1” brzmi jak surowy log, a nie jak zdanie.
	static func komunikatONowych(_ liczba: Int) -> String? {
		guard liczba > 0 else { return nil }
		let rzeczownik = PolishPluralization.nounForm(
			for: liczba,
			singular: "nowa treść",
			few: "nowe treści",
			many: "nowych treści"
		)
		return "\(liczba) \(rzeczownik) na górze listy"
	}
}
