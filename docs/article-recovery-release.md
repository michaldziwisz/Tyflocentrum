# Poprawka ładowania artykułów: iOS 1.0.2 (3)

## Zakres i stan

Poprawki wprowadzono dla iOS i Androida. Michał zaakceptował próbę iOS w TestFlight i zlecił publikację obu platform w sklepach. Wersja iOS **1.0.2, build 3** została zgłoszona do App Store: odczyt API potwierdził `WAITING_FOR_REVIEW` i `releaseType=AFTER_APPROVAL`. Po zatwierdzeniu przez Apple publikacja nastąpi automatycznie. Nie jest to jeszcze potwierdzenie publicznej dostępności. Powiadomienia push pozostają odłożone.

W zgłoszeniu wykorzystano ten sam build z TestFlight, bez przebudowy i ponownego uploadu. Identyfikator wersji: `25b5b106-c34e-447b-a0af-99b609449467`; zgłoszenia: `2daf8bb2-f499-422c-be75-f8ad423e2ae6`; czas wysłania: `2026-09-20T14:01:47.901Z`. Polska lokalizacja ASC to `pl`. Nową notatkę zmian odczytano po zapisie; zachowane zrzuty iPhone oraz iPad mają stan `COMPLETE`, a dane kontaktowe i informacje dla recenzenta są kompletne. Stan recenzji należy ponownie odczytywać w ASC, ponieważ zmienia go Apple.

Kod przygotowano w oddzielnych worktree. Odczyt skrótów potwierdził zachowanie wszystkich zastanych lokalnych plików prac nad push: 25 w iOS i 30 w Androidzie. Nie używano stash, reset ani przełączania gałęzi w tych brudnych katalogach. Naprawy znajdują się w osobnych gałęziach i PR-ach; lokalną pracę nad push należy później świadomie połączyć z nową bazą.

## Kryteria odbioru

- [x] iOS rozróżnia próbę, sukces i błąd wyświetlania HTML.
- [x] Po awarii renderowania następuje najwyżej jedno automatyczne odzyskanie w danym cyklu, potem dostępne jest ponowienie ręczne.
- [x] Zdrowy dokument nie jest przeładowywany przy zwykłej aktualizacji SwiftUI.
- [x] Android umożliwia ponowienie pobrania bez opuszczania artykułu.
- [x] Pobieranie ma ograniczony budżet prób, respektuje anulowanie i odróżnia błędy przejściowe od trwałych.
- [x] Ręczne pobranie omija cache, a odpowiedź jest walidowana przed jego aktualizacją.
- [x] Testy UI iOS sprawdzają rzeczywisty akapit w WKWebView, nie dodatkową etykietę ani sam kontener.
- [x] Pełne testy jednostkowe, APK i lint Androida wykonane.
- [x] Testy Xcode z UIKit/WebKit oraz testy UI wykonane na macOS.
- [x] Niezależne końcowe recenzje obu implementacji zaakceptowane.
- [x] Apple przetworzyło build, a API potwierdza dostęp builda i Michała w tej samej wewnętrznej grupie TestFlight.

## Dowody iOS

- Kod: PR [#3](https://github.com/michaldziwisz/Tyflocentrum/pull/3), commit `67e97aee21aa43fe3aa8e700817315f2bb9dd680`; merge `a2a0524362b291167fc74bab0f0c9b325ccbe6ba`. Drzewa kodu po scaleniu i po testach są identyczne.
- [Pełny CI](https://github.com/michaldziwisz/Tyflocentrum/actions/runs/35512429977): **204 testy zaliczone, zero błędów i pominięć**. Symulator iPhone 17 Pro, iOS 26.5.
- Zweryfikowano wykonanie obu nowych testów odzyskiwania, 13 testów stanu HTML i siedmiu testów koordynacji z nawigacją WebKita. Pobrano i obejrzano trzy zrzuty: automatyczne odzyskanie, przycisk po wyczerpaniu automatycznej próby oraz treść po ręcznym ponowieniu. Akapit kontrolny jest czytelny po obu ścieżkach; stan błędu oferuje „Wczytaj treść ponownie”.
- [Podpis i upload](https://github.com/michaldziwisz/Tyflocentrum/actions/runs/35513941158): Apple potwierdziło walidację i `UPLOAD SUCCEEDED with no errors`.
- Build/Delivery UUID: `f143647f-672f-4dcf-b171-69d0fe6bcae6`.
- Odczyt App Store Connect: `processingState=VALID`, `internalBuildState=IN_BETA_TESTING`, build niewygasły, obecny w grupie `ee7203f3-b70a-47fe-8222-0e6aa15476ea`; członkostwo Michała potwierdzone.
- Dodano polską notatkę „Co testować” i potwierdzono jej treść ponownym odczytem.
- Podpisana IPA: `net.tyflopodcast.tyflocentrum`, 1.0.2 (3), SDK `iphoneos26.5`, profil dystrybucyjny (`get-task-allow=false`). SHA-256: `5f1427613b3f2a52e10001964c2961b108ec9342f639f93faa8d570f0aae760c`.
- W rozpakowanej binarce Release potwierdzono brak flag kontrolowanych awarii `UI_TESTING_SAFE_HTML_FAIL_ONCE/TWICE` i obecność tekstu rzeczywistego przycisku odzyskiwania.

## Dowody Androida

- [PR #2](https://github.com/michaldziwisz/tyflocentrum_android/pull/2), commit `b7d903888dccf2e562c4cbdedc56386cbd0f089a`.
- `testDebugUnitTest assembleDebug lintDebug`: **41 testów zaliczonych**, zero błędów i pominięć. Lint: zero błędów, 17 ostrzeżeń.
- Testy obejmują timeout próby i całości, anulowanie przez wywołującego, Retry-After, walidację i kolejność cache, trwałe błędy TLS oraz spóźniony wynik starego loadera.
- Poprawkę początkowo sprawdzono w APK debug bez instalacji i publikacji. Po akceptacji Michała przygotowano **1.0.9 (versionCode 10)** i wysłano podpisany AAB na ścieżkę produkcyjną Google Play. [Przebieg publikacji](https://github.com/michaldziwisz/tyflocentrum_android/actions/runs/35515451040) zakończył się sukcesem. Ponowny odczyt API potwierdził `production`, `versionCodes=[10]`, `status=completed`, brak ograniczenia udziału i właściwą polską notatkę zmian. Pojawienie się aktualizacji na konkretnym telefonie może być opóźnione przez sklep. Szczegóły: `docs/wydanie-1.0.9.md` w repo Androida.

## Dodatkowa naprawa bramki i ograniczenia

W zastanym `StrategiaOdswiezaniaTests.swift` dwie asercje nie kompilowały się przez przekazanie `TimeInterval?` do porównania z `accuracy`. Użyto `try XCTUnwrap`, bez zmiany logiki odświeżania. Pełny przebieg Xcode potwierdził wykonanie tych testów.

Nie odtworzono pierwotnej sporadycznej awarii na fizycznym iPhonie. Testy kontrolowanych awarii potwierdzają odzyskiwanie, lecz symulator nie zastępuje odsłuchu VoiceOver. Michał po próbie wydania w TestFlight potwierdził „jest ok” i zatwierdził publikację. Nie opisano szczegółów jego próby, więc nie jest to odrębny pełny audyt VoiceOver. Testy JVM i APK nie są pomiarem TalkBacka ani Jeshuo.
