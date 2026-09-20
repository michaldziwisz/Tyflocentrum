# Poprawka ładowania artykułów: zakres wydania testowego

## Zatwierdzony zakres

Michał zatwierdził implementację poprawek na iOS i Androidzie oraz dostarczenie wyłącznie wersji iOS przez TestFlight. Bez publikacji do App Store i Google Play. Powiadomienia push pozostają odłożone.

Kod powstaje w oddzielnych worktree opartych na wydanych gałęziach, bez importowania lokalnych zmian push. Przed rozpoczęciem zapisano skróty plików i diff istniejącej pracy. Nie używamy stash, reset ani przełączania gałęzi w katalogach zawierających te zmiany.

## Kryteria odbioru

- [ ] iOS rozróżnia ładowanie, sukces i błąd wyświetlania HTML.
- [ ] Po awarii renderowania następuje najwyżej jedno automatyczne odzyskanie, następnie dostępne ponowienie ręczne.
- [ ] Poprawna treść nie jest przeładowywana przy zwykłej aktualizacji SwiftUI.
- [ ] Android umożliwia ponowienie pobrania bez opuszczania artykułu.
- [ ] Pobieranie ma ograniczony budżet prób, respektuje anulowanie i odróżnia błędy przejściowe od trwałych.
- [ ] Ręczne ponowienie pobrania omija nieaktualną pamięć, a błędna odpowiedź nie zostaje w niej jako poprawna.
- [ ] Testy sprawdzają tekst artykułu, nie tylko obecność kontenera.
- [ ] Testy jednostkowe i build Androida wykonane.
- [ ] Pełne testy Xcode z UIKit/WebKit i testami UI wykonane na macOS.
- [ ] Recenzja zmian wykonana niezależnie od autorów.
- [ ] Build iOS przetworzony przez Apple i dostępny w wewnętrznej grupie TestFlight Michała.

## Numer wersji

Odczyt App Store Connect przed pracą: wersja 1.0.1 jest wydana, najwyższy numer builda to 2. Planowana paczka testowa: **1.0.2, build 3**. Sam upload do TestFlight nie oznacza zgłoszenia wersji do recenzji App Store.

## Zastana blokada testów

Ostatni przebieg CI na bazowym commicie `3120fc9`, run `35256332696`, nie uruchomił testów: dwie asercje w `StrategiaOdswiezaniaTests.swift` przekazywały `TimeInterval?` do wariantu `XCTAssertEqual` z `accuracy`. Zmieniono je na jawne `try XCTUnwrap`, bez modyfikowania logiki odświeżania. Oba testy wykonane z prawdziwym rdzeniem na Swift Linux przeszły. Pełny Xcode pozostaje osobną bramką.

## Ograniczenia

Testy symulatora nie zastępują fizycznego iPhone’a ani odsłuchu VoiceOver. Analogicznie testy JVM/kompilacja nie są testem TalkBacka i Jeshuo. TestFlight służy dalszej weryfikacji zachowania na urządzeniu.
