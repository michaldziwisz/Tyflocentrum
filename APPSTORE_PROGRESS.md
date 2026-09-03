# Tyflocentrum — App Store readiness (postęp prac)

Aktualizacja: **2026-09-03** (poprzednia: 2026-01-29)

Ten plik jest „żywą” check‑listą wdrożeń pod wydanie **1.0** (App Store) na podstawie `CODE_REVIEW_APPSTORE.md`.

## Stan CI — sprostowanie wobec poprzedniej wersji tego dokumentu

Poprzednia wersja mówiła: „workflow `iOS (unsigned IPA)` – **success** (run `21495748088`)”. To była prawda **w styczniu** i przestała nią być bez żadnej zmiany w kodzie.

Stan faktyczny, ustalony 03.09.2026:

- ostatni zielony przebieg: 29.01.2026 (`21495748088`),
- trzy kolejne przebiegi (marzec ×2, czerwiec) — **czerwone**, każdy padał **po 13 sekundach** na lincie SwiftFormat,
- czyli od marca do września **build i testy w ogóle się nie uruchamiały** i nie było wiadomo, czy kod się kompiluje.

Dwie niezależne przyczyny, żadna z nich to „zły kod”:

1. **Nieprzypięta wersja narzędzia.** Skrypt lintu pobierał SwiftFormat przez `brew install`, czyli zawsze najnowszy, a kolejne wydania dodają reguły. Dowód rozstrzygający: `Tyflocentrum/SettingsStore.swift` oblewał lint, choć nie był tknięty od zielonego przebiegu. Pomiar na tym repo: wersja `0.58.7` → 1 plik z 63 do formatowania, wersja `0.63.0` → 22 z 63.
2. **Za stare SDK**, widoczne dopiero po naprawie pierwszej przyczyny. Commit `703e94d` z upstreamu („Fix: compiler warnings across the app”) podmienił API na symbole z nowszego SDK — `AVAudioSession.CategoryOptions.allowBluetoothHFP` oraz `AVAssetExportSession.export(to:as:)`. Na Xcode 15.4 kod **nie kompilował się wcale**.

Stan po naprawie (run `33773299584`, obraz `macos-26`, Xcode 26.6): lint przechodzi, kod się kompiluje, testy się wykonują — **144 zaliczone, 2 padające** (patrz niżej).

## Wymóg wydawniczy, który zmienia wybór obrazu CI

Od **28.04.2026** aplikacje wysyłane do App Store Connect muszą być budowane **Xcode 26 na SDK iOS 26** (`developer.apple.com/news/upcoming-requirements`). Obraz `macos-14` (Xcode 15.4) jest dodatkowo oznaczony przez GitHuba jako wycofywany, więc nawet zielony build na nim **nie nadawałby się do wydania**. CI stoi teraz na `macos-26`, z wersją przypiętą jawnie — `macos-latest` wędruje i sam zmieniłby SDK w trakcie życia projektu.

## Wdrożone (bez Apple Developer Program)

Z iteracji styczniowej:

- Usunięto martwy, legacy kod renderowania HTML (`HTMLTextView`, `HTMLRendererHelper`).
- Push (na teraz): UI i automatyczna rejestracja powiadomień są ukryte/wyłączone w buildzie Release (żeby nie dostarczać „pozornej” funkcji).
- Zoptymalizowano `Podcast.PodcastTitle.plainText` (memoizacja + szybka ścieżka bez parsowania HTML) i dodano testy regresji.
- Migracja `NavigationView` → `NavigationStack` w głównych widokach.
- `TyfloAPI`: dla requestów WordPress domyślne `cachePolicy = .useProtocolCachePolicy` (a dla endpointów „na żywo” wymuszone `reloadIgnoringLocalCacheData`) + testy regresji.
- SwiftFormat: dodano `.swiftformat` + `.swift-version`, lint w CI oraz workflow `SwiftFormat` do automatycznego formatowania bez Maca.
- `TyfloAPI`: dodano in‑memory cache z TTL (5 min) dla odpowiedzi z `cache-control: no-store` + testy regresji.
- `TyfloAPI`: dodano limity pamięci dla cache `no-store` (max wpisów / max bajtów / max rozmiar pojedynczej odpowiedzi) + testy ewikcji.
- Logowanie: `print(...)` zastąpiono `Logger` (`os_log`) i ograniczono logowanie „wrażliwych” URL-i (bez querystringów).
- Ustabilizowano nawigację z menu aplikacji (żeby UI testy i nawigacja były deterministyczne).
- iPad/Mac: ukryto i wyłączono iPhone‑only „tryb ucha” (proximity) w ekranie głosówek + testy regresji.
- `SafeHTMLView`: odświeża font-size po zmianie Dynamic Type (żeby treść HTML reagowała na ustawienia).
- Projekt: ujednolicono niespójne build settings (`IPHONEOS_DEPLOYMENT_TARGET`).
- Daty: zabezpieczono współdzielenie `DateFormatter` w `Podcast.formattedDate` (uniknięcie problemów przy concurrency).

Z iteracji 03.09.2026:

- **CI odblokowane**: wersja SwiftFormat przypięta, z bramką przerywającą pracę, gdy binarka podaje inną wersję (samo przypięcie bez kontroli jest deklaracją, nie mechanizmem). Dowód: `scripts/test-bramka-wersji-swiftformat.sh`, 7 asercji z kontrolą negatywną.
- **Build na `macos-26`** (Xcode 26 / SDK iOS 26), zgodnie z wymogiem wydawniczym powyżej.
- **`PrivacyInfo.xcprivacy`** — patrz „Bloker, który wcześniej był opisany jako opcjonalny”.
- **`ITSAppUsesNonExemptEncryption = false`** w `Info.plist`: aplikacja używa wyłącznie HTTPS/TLS systemu, bez własnej kryptografii. Bez tego klucza App Store Connect zadaje pytanie eksportowe przy każdej wysyłce builda.
- **Bundle ID targetów testowych**: `com.nunosoft.TyflocentrumTests`/`UITests` → `net.tyflocentrum.app.Tests`/`UITests`. Sama aplikacja miała już `net.tyflocentrum.app`.
- **Zero `try!` w kodzie produkcyjnym**: oba wystąpienia w `ShowNotesParser` zamienione na wartości opcjonalne. Wzorce są stałe, więc kompilacja praktycznie nie może się nie udać — ale `try!` znaczy „wywal aplikację, gdyby jednak”, a przy literówce w przyszłej edycji ubijałoby to apkę przy wejściu w notatki audycji. Koszt zmiany zerowy, bo oba wzorce służą wyłącznie do `firstMatch`.
- **Ikona ujednolicona z wersją Windows i Android** — stara ikona iOS (`App for Arek-*.png`) była zupełnie inną grafiką i jedyną z trzech platform bez wrześniowego ujednolicenia. Kontrast symbolu do tła **8,12:1** przy progu 3:1 (WCAG 1.4.11), zgodność kształtu z ikoną Androida **99,0%** (stara ikona: 14,8%, czyli miara rozróżnia). Narzędzia: `tools/generuj_ikone_ios.py`, `tools/test_ikony_ios.py`.

## Bloker, który wcześniej był opisany jako opcjonalny

`CODE_REVIEW_APPSTORE.md` wymieniał `PrivacyInfo.xcprivacy` w sekcji „wysoki priorytet” ze słowem „(Opcjonalnie)”. **Nie jest opcjonalny.** Apple pisze wprost: „Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect”.

Kod używa dwóch kategorii wymagających deklaracji — ustalonych skanem kodu, nie domysłem:

| kategoria | gdzie w kodzie | powód |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `AudioPlayer`, `DiagnosticsStore`, `FavoritesStore`, `SettingsStore`, `TyflocentrumApp`, `ArticlesCategoriesView`, `ContactView` | `CA92.1` — dane dostępne wyłącznie tej aplikacji |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `VoiceMessageRecorder` (`.fileSizeKey`, 3 miejsca) | `C617.1` — metadane plików w kontenerze aplikacji |

Manifest jest podpięty do fazy **Resources** targetu. To istotne: plik leżący tylko na dysku, bez wpisu w „Copy Bundle Resources”, nie trafia do builda — czyli App Store by go nie zobaczył, a my mielibyśmy fałszywe poczucie zamkniętej sprawy. Dowód: `tools/test_manifest_prywatnosci.py` (15 asercji) sprawdza to wprost i porównuje manifest z kodem **w obie strony**: brak deklaracji oznacza odrzucenie wysyłki, a deklaracja „na zapas” to nieprawdziwe oświadczenie wobec Apple.

## Zamknięte: dwa padające testy — oba miały INNE przyczyny, niż zakładano

Pierwotna hipoteza mówiła „oba dotyczą wyścigów”. Pomiary pokazały, że była błędna
w obu przypadkach.

1. `NewsFeedViewModelTests.testLoadMoreInFlightDoesNotPolluteRefreshResults` —
   **defekt testu, nie kodu**. Blokada semafora trwała 2 s, czyli dokładnie tyle,
   ile `requestTimeoutSeconds` w tym samym teście: test mierzył, która z dwóch
   równych liczb zdąży pierwsza. Po skróceniu blokady do 0,4 s przechodzi
   w 0,44 s, wcześniej zajmował 2,6 s i padał. Kod produkcyjny bez zmian.
   Wniosek: **dwie równe liczby w teście to nie próg, to wyścig.**

2. `testListsRecover…` — **defekt APLIKACJI, ujawniony przez test.** Zrzut ekranu
   z momentu padnięcia (mechanizm niżej) pokazał ekran Podcasty z samym wierszem
   „Wszystkie kategorie” i **zupełną pustką** pod nim: bez komunikatu, bez
   kręciołka, bez przycisku. `AsyncListStatusSection` miał trzy gałęzie (błąd,
   ładowanie, pusto po udanym pobraniu) i stan „pusto, bez błędu, `hasLoaded`
   fałszywe” nie pasował do żadnej — więc widok nie renderował niczego. Trafia się
   tam, gdy `refresh` wyjdzie przez `Task.isCancelled` przed ustawieniem
   `hasLoaded` (SwiftUI anuluje `.task` przy przełączaniu zakładek), a
   `guard !hasLoaded` blokował ponowną próbę na stałe.

   Naprawione po obu stronach: czwarta gałąź pokazuje komunikat i przycisk,
   a `loadIfNeeded` podejmuje próbę, gdy lista została pusta bez błędu.
   Potwierdzone wzrokowo na kolejnym zrzucie: jest karta „Nie udało się pobrać
   danych. Spróbuj ponownie.” z klikalnym przyciskiem. Naprawa objęła wszystkie
   cztery widoki korzystające z tej sekcji (widać to też na ekranie Szukaj).

   Sam test został przepisany na `testListsRecoverWhenFirstRequestFails`: nazwa
   obiecywała odtworzenie „automatycznie”, a projekt aplikacji mówi co innego —
   ponowienia są w warstwie API (`withRetry`, 2 próby) i w modelu listy (trzecia),
   ale gdy wszystkie padną, użytkownik **ma** dostać jawną drogę wyjścia. Test
   klika teraz „Spróbuj ponownie”, czyli robi to co użytkownik, i nadal wywala
   się, gdy brakuje i danych, i przycisku — czyli w jedynym realnie złym stanie.

### Trzecia rzecz, którą wykrył ten sam mechanizm

`testCanAddPodcastToFavoritesAndSeeItInFavorites` padł raz na trzy przebiegi,
a zrzut z padnięcia pokazywał ekran **całkowicie poprawny**. Log wyjaśnił dlaczego:
na tym runnerze `Wait for app to idle` zajmowało do **143 s**, a start aplikacji
52 s zamiast typowych 2-3 s. Przy limitach 5 s test mierzył obciążenie maszyny,
nie zachowanie aplikacji. Limity zebrano w jedno miejsce (`limitUI`, domyślnie
30 s, nadpisywalne przez `LIMIT_UI_SEKUNDY`).

### Przyrząd, bez którego to wszystko było zgadywaniem

`tearDown` dołącza zrzut ekranu, gdy test padnie; skrypt przekazuje
`-resultBundlePath`, a workflow wystawia `.xcresult` jako artefakt z `if: always()`.
Trzy poprzednie cykle diagnozy (po ~27 minut każdy) nie przybliżyły odpowiedzi,
bo padający test mówi tylko „`XCTAssertTrue` failed w linii N”. Pierwszy zebrany
zrzut rozstrzygnął dwie sprawy naraz. **Koszt narzędzia zwrócił się w pierwszym
użyciu** — przy zmianach w UI warto je mieć od początku, nie po trzeciej porażce.

Do pomiaru powtarzalności służy `.github/workflows/diagnostyka-testu.yml`:
uruchamia wskazane testy N razy, każdy z osobnym `derivedDataPath` (wspólny
cache'owałby wynik i przebiegi nie byłyby niezależne), i kończy się kodem 0, bo
jest przyrządem pomiarowym, nie bramką jakości. **Uwaga:** `workflow_dispatch`
czyta definicję z gałęzi domyślnej, więc ten workflow da się uruchomić dopiero po
scaleniu do `master`.

## Wymaga Apple Developer Program / zewnętrznej konfiguracji

- Realne powiadomienia push przez APNs:
  - capability **Push Notifications** + entitlements dla docelowego bundle ID,
  - klucz APNs (`.p8`) + `teamId` + `keyId`,
  - faktyczna wysyłka do APNs w `push-service` (obecnie MVP tylko loguje fan‑out).
- Podpisanie i wysyłka builda: certyfikat dystrybucyjny + profil (do wystawienia przez App Store Connect API, bez Maca) oraz klucz ASC API jako sekrety repo.

## Do zrobienia poza kodem (App Store Connect)

- Dodać **Privacy Policy URL** oraz **Support URL**.
- Uzupełnić „App Privacy” zgodnie z realnym działaniem aplikacji (kontakt, głosówki, ulubione/ustawienia; push jeśli zostanie włączony). Musi być spójne z `PrivacyInfo.xcprivacy` — rozbieżność jest częstym powodem odrzucenia.
- Zrzuty ekranu iPhone **i iPad** (projekt ma `TARGETED_DEVICE_FAMILY = "1,2"`).
- Przygotować notatki do App Review (co i gdzie przetestować, jak zachowuje się kontakt poza godzinami audycji).

## Kandydaci na kolejne iteracje (nie blokują 1.0)

- ✅ Dołożono narzędzie do automatycznego formatowania (**SwiftFormat**) i ustandaryzowano styl w repo (lint w CI).
- ✅ Dodano „prawdziwy” cache (in‑memory + TTL) dla endpointów z `cache-control: no-store` (z testami).
- `PodcastTitle.plainTextCache`: `totalCostLimit` po długości stringa, jeśli w praktyce cache rośnie pamięciowo.
- Doprecyzowanie strategii cache (per‑endpoint TTL, invalidation), jeśli użytkownicy zgłoszą „nieaktualne” treści.
