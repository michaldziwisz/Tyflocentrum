//
//  StylPrzyciskuAkcji.swift
//  Tyflocentrum
//
//  Wspólny styl przycisków akcji (prędkość, znaczniki czasu, odnośniki,
//  ulubione, kontakt) — wyśrodkowany, pogrubiony, o zmierzonym kontraście.
//
//  DLACZEGO POWSTAŁ. Zgłoszenie od użytkowników: te przyciski są słabo widoczne
//  przy zwiększonym kontraście. Pomiar na zrzucie ekranu (1320×2868, iPhone
//  17 Pro Max) potwierdził to liczbowo:
//
//    granica szarego przycisku vs tło strony  1,21:1  przy progu 3:1   PONIŻEJ
//    tekst niebieski na szarym tle            2,90:1  przy progu 4,5:1 PONIŻEJ
//
//  Czyli domyślny `.bordered` z systemowym szarym wypełnieniem NIE SPEŁNIA
//  WCAG 1.4.11 (granica kontrolki) ani 1.4.3 (tekst). Przy słabym wzroku
//  granica takiego przycisku zlewa się z białym tłem.
//
//  DLACZEGO NIE SAM `.borderedProminent`. Też zmierzone: biały tekst na
//  systemowym niebieskim (0, 136, 255) daje 3,52:1, czyli nadal poniżej progu
//  4,5:1 dla tekstu. Dlatego kolor jest przyciemniony do (0, 90, 200):
//
//    biały tekst na (0, 90, 200)              6,37:1  przy progu 4,5:1 OK
//    (0, 90, 200) vs tło strony               6,37:1  przy progu 3:1   OK
//
//  Wartości są weryfikowane testem `tools/test_kontrast_przyciskow.py`, który
//  czyta je WPROST z tego pliku — więc zmiana koloru bez sprawdzenia kontrastu
//  wywali test, a nie przejdzie niezauważona.
//
//  POZOSTAŁE DECYZJE, wszystkie z tego samego powodu (słaby wzrok + powiększenie):
//  - `.frame(maxWidth: .infinity)` — przycisk zajmuje całą szerokość, więc jest
//    większym celem i ma przewidywalne położenie; przy powiększeniu ekranu nie
//    trzeba go szukać wzrokiem po prawej stronie,
//  - `.fontWeight(.semibold)` — pogrubienie, o które prosili użytkownicy,
//  - `multilineTextAlignment(.center)` — etykieta wyśrodkowana także wtedy, gdy
//    przy dużej czcionce łamie się na dwie linie,
//  - `.minimumScaleFactor(0.8)` — przy Dynamic Type XXL tekst raczej się zmniejszy
//    niż zostanie ucięty; nie schodzimy niżej, bo to psułoby czytelność,
//  - `.contentShape(...)` — całe pole jest klikalne, nie tylko litery. Kształt
//    dopasowany do widocznego tła, NIE `Rectangle()`: prostokąt większy niż tło
//    zepsuł dwa testy UI czekające na zmianę etykiety przycisku ulubionych
//    (szczegóły przy samym wywołaniu, niżej).

import SwiftUI

/// Kolory stylu. Osobny typ, żeby test miał gdzie po nie sięgnąć,
/// a wartości nie były rozsypane po widokach.
enum KoloryPrzyciskuAkcji {
	/// Wypełnienie przycisku głównego. Przyciemniony systemowy niebieski —
	/// domyślny (0, 136, 255) nie daje 4,5:1 dla białego tekstu.
	static let wypelnienieRGB = (r: 0, g: 90, b: 200)

	/// Obramowanie przycisku drugorzędnego. Ten sam kolor co wypełnienie,
	/// żeby granica kontrolki spełniała 1.4.11 również bez tła.
	static let obramowanieRGB = (r: 0, g: 90, b: 200)

	static var wypelnienie: Color {
		Color(red: Double(wypelnienieRGB.r) / 255,
		      green: Double(wypelnienieRGB.g) / 255,
		      blue: Double(wypelnienieRGB.b) / 255)
	}

	static var obramowanie: Color {
		Color(red: Double(obramowanieRGB.r) / 255,
		      green: Double(obramowanieRGB.g) / 255,
		      blue: Double(obramowanieRGB.b) / 255)
	}
}

/// Przycisk główny: biały tekst na wypełnieniu.
struct StylPrzyciskuAkcji: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.body)
			.fontWeight(.semibold)
			.multilineTextAlignment(.center)
			.minimumScaleFactor(0.8)
			.foregroundStyle(.white)
			.padding(.vertical, 12)
			.padding(.horizontal, 16)
			.frame(maxWidth: .infinity)
			.background(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(KoloryPrzyciskuAkcji.wypelnienie)
			)
			// Ten sam powod co w wariancie obramowanym ponizej: kształt dotyku
			// dopasowany do widocznego tla, nie wiekszy prostokat.
			.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.opacity(configuration.isPressed ? 0.75 : 1)
	}
}

/// Przycisk drugorzędny: kolorowy tekst na przezroczystym tle, ale z WYRAŹNYM
/// obramowaniem. Obramowanie jest tu istotą, nie ozdobą — bez niego granica
/// kontrolki miała 1,21:1 i znikała przy słabym wzroku.
struct StylPrzyciskuAkcjiObramowany: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.body)
			.fontWeight(.semibold)
			.multilineTextAlignment(.center)
			.minimumScaleFactor(0.8)
			.foregroundStyle(KoloryPrzyciskuAkcji.obramowanie)
			.padding(.vertical, 12)
			.padding(.horizontal, 16)
			.frame(maxWidth: .infinity)
			.background(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(KoloryPrzyciskuAkcji.obramowanie, lineWidth: 2)
			)
			// UWAGA: tu było `.contentShape(Rectangle())`. Powiększa obszar dotyku,
			// ale prostokąt jest WIĘKSZY niż zaokrąglone tło i wchodzi w drzewo
			// dostępności jako osobny kształt. Zmierzone: po jego dodaniu padły
			// dwa testy UI czekające na zmianę etykiety „Dodaj do ulubionych” ->
			// „Usuń z ulubionych” (run 33795666482, linie 394 i 483), a wcześniej
			// oba przechodziły. Skoro test przestał widzieć nową etykietę, to
			// VoiceOver również może nie ogłaszać aktualnego stanu — a dla tej
			// aplikacji to defekt krytyczny, nie kosmetyczny.
			//
			// Kształt dopasowany do tła zachowuje powiększony obszar dotyku
			// (padding + maxWidth nadal działają), bez wprowadzania geometrii
			// rozbieżnej z tym, co widać.
			//
			// UCZCIWIE: nie mam dowodu, że to JEDYNA przyczyna tamtych dwóch
			// padnięć — potwierdzi to dopiero kolejny przebieg CI. Gdyby testy
			// nadal padały, następnym krokiem jest zrzut ekranu w momencie
			// porażki, nie kolejna zmiana na wyczucie.
			.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.opacity(configuration.isPressed ? 0.75 : 1)
	}
}

extension ButtonStyle where Self == StylPrzyciskuAkcji {
	static var akcja: StylPrzyciskuAkcji { StylPrzyciskuAkcji() }
}

extension ButtonStyle where Self == StylPrzyciskuAkcjiObramowany {
	static var akcjaObramowana: StylPrzyciskuAkcjiObramowany { StylPrzyciskuAkcjiObramowany() }
}
