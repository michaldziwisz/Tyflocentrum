# Tyflocentrum

Tyflocentrum to aplikacja iOS napisana w **SwiftUI**, która agreguje i udostępnia treści z serwisów Tyflo:

- **Podcasty** z Tyflopodcast (lista, wyszukiwarka, komentarze, odtwarzacz),
- **Artykuły** z Tyfloświat (czytnik treści HTML),
- **Tyfloradio** (stream na żywo) + opcja **kontaktu z radiem** podczas audycji interaktywnej.

Projekt jest w pełni natywny (bez zewnętrznych zależności), z naciskiem na **dostępność (VoiceOver)** oraz wygodę odsłuchu (pilot systemowy, szybkość, wznawianie).

## Funkcje aplikacji

- **Nowości**: wspólny feed podcastów i artykułów, z doładowywaniem starszych treści.
- **Podcasty**: lista kategorii → lista audycji → szczegóły + komentarze.
- **Artykuły**: lista kategorii → lista artykułów → bezpieczne renderowanie HTML.
- **Szukaj**: wyszukiwanie audycji po frazie.
- **Odtwarzacz**:
  - play/pause, przewijanie ±30s, suwak pozycji,
  - zmiana prędkości odtwarzania,
  - wznawianie odsłuchu (zapamiętana pozycja per URL),
  - integracja z ekranem blokady / pilotem (`MPRemoteCommandCenter`),
  - obsługa **Magic Tap** (VoiceOver) do przełączania odtwarzania.
- **Dodatki do audycji** (jeśli dostępne): znaczniki czasu i odnośniki (parsowane z komentarzy Tyflopodcast).

## Wymagania

- iOS **17.0+** (`IPHONEOS_DEPLOYMENT_TARGET = 17.0` w `Tyflocentrum.xcodeproj/project.pbxproj`)
- Xcode **15+** (Swift 5)
- (opcjonalnie) GitHub CLI `gh` – do pobierania unsigned IPA z GitHub Actions.

## Uruchomienie (dla użytkownika)

To repozytorium zawiera źródła aplikacji. Najprościej uruchomić ją lokalnie z Xcode.

### Uruchomienie z Xcode

1. Otwórz `Tyflocentrum.xcodeproj` w Xcode.
2. Wybierz scheme `Tyflocentrum`.
3. Uruchom na symulatorze lub urządzeniu.

Jeśli uruchamiasz na urządzeniu, możesz potrzebować własnego Teamu/Provisioningu (ustawienia Signing w Xcode).

### Gotowa paczka (unsigned IPA) z CI

Repo zawiera workflow GitHub Actions `iOS (unsigned IPA)` (`.github/workflows/ios-unsigned-ipa.yml`), który:

- uruchamia testy na symulatorze,
- buduje archiwum bez podpisu,
- pakuje `.app` do unsigned `.ipa`,
- publikuje artifact `Tyflocentrum-unsigned-ipa`.

Do pobrania artifactu można użyć skryptu `scripts/fetch-ipa.sh` (wymaga `gh` oraz zalogowania do GitHuba):

```bash
./scripts/fetch-ipa.sh                # pobierze ostatni udany run na gałęzi master
./scripts/fetch-ipa.sh <run_id>       # pobierze konkretny run (databaseId)
```

Domyślnie skrypt zapisuje plik do `artifacts/tyflocentrum.ipa`.

> Uwaga: `.ipa` jest **niepodpisana**, więc do instalacji potrzebujesz narzędzia do sideloadingu (np. AltStore/Sideloadly) i odpowiedniej konfiguracji Apple ID/certyfikatów.

## Architektura (dla programistów)

### Przegląd warstw

Wysokopoziomowo aplikacja składa się z:

- **UI (SwiftUI)** – `Tyflocentrum/Views/*`
- **Warstwa danych (sieć)** – `Tyflocentrum/TyfloAPI.swift`
- **Audio** – `Tyflocentrum/AudioPlayer.swift`
- **Renderowanie HTML** – `Tyflocentrum/Views/SafeHTMLView.swift`
- **(Przygotowane) Core Data** – `Tyflocentrum/DataController.swift` + `Tyflocentrum.xcdatamodeld`

Punkt startowy aplikacji to `Tyflocentrum/TyflocentrumApp.swift`, który wstrzykuje przez `Environment` / `EnvironmentObject`:

- `DataController` (`managedObjectContext`)
- `TyfloAPI`
- `AudioPlayer`

### Nawigacja i główne ekrany

`Tyflocentrum/Views/ContentView.swift` definiuje `TabView` z pięcioma zakładkami:

- `NewsView` – feed Nowości (podcasty + artykuły),
- `PodcastCategoriesView` – kategorie podcastów,
- `ArticlesCategoriesView` – kategorie artykułów,
- `SearchView` – wyszukiwarka podcastów,
- `MoreView` – Tyfloradio + kontakt z radiem.

### Sieć (`TyfloAPI`)

`Tyflocentrum/TyfloAPI.swift` obsługuje asynchroniczne pobieranie danych:

- WordPress REST API:
  - `https://tyflopodcast.net/wp-json/wp/v2/...` (podcasty, kategorie, komentarze)
  - `https://tyfloswiat.pl/wp-json/wp/v2/...` (artykuły, kategorie)
- Kontakt z radiem:
  - `https://kontakt.tyflopodcast.net/json.php?ac=current` (sprawdzenie dostępności audycji)
  - `https://kontakt.tyflopodcast.net/json.php?ac=add` (wysyłka wiadomości, JSON `ContactResponse`)
- Link do odsłuchu audycji:
  - `https://tyflopodcast.net/pobierz.php?id=<postID>&plik=0` (`getListenableURL(for:)`)

Modele danych znajdują się w `Tyflocentrum/Models/*` (m.in. `Podcast`, `WPPostSummary`, `Category`, `Comment`, `Availability`).

### Feed “Nowości”

`NewsView` używa `NewsFeedViewModel`, który łączy dwie paginowane listy (`podcast` i `article`) w jeden strumień posortowany po dacie.

Do pobierania stron wykorzystywane są:

- `fetchPodcastSummariesPage(page:perPage:)`
- `fetchArticleSummariesPage(page:perPage:)`

### Audio (`AudioPlayer` + `MediaPlayerView`)

- `Tyflocentrum/AudioPlayer.swift` to wrapper na `AVPlayer`:
  - integruje się z `MPRemoteCommandCenter`,
  - aktualizuje `MPNowPlayingInfoCenter` (tytuł, podtytuł, czas, prędkość),
  - wspiera live stream (`isLiveStream`) i pliki VOD (seek/prędkość),
  - zapisuje pozycję odsłuchu w `UserDefaults` (klucz: `resume.<url>`).
- UI odtwarzacza: `Tyflocentrum/Views/MediaPlayerView.swift`.

### Bezpieczne renderowanie HTML (`SafeHTMLView`)

Artykuły są renderowane w `WKWebView`, ale w sposób ograniczający ryzyka:

- `WKWebsiteDataStore.nonPersistent()` (brak trwałych cookies/storage),
- JavaScript wyłączony,
- własny dokument HTML z CSP (blokada skryptów, ramek i nawigacji),
- restrykcje nawigacji (tylko dozwolony host w głównej ramce).

Implementacja: `Tyflocentrum/Views/SafeHTMLView.swift`.

### Znaczniki czasu i odnośniki (Show Notes)

`Tyflocentrum/ShowNotesParser.swift` parsuje komentarze (HTML → tekst) i wyciąga:

- **znaczniki czasu** (np. `00:02:54`),
- **odnośniki** i e-maile (zamieniane na `mailto:`).

W UI: `MediaPlayerView` pokazuje przyciski “Znaczniki czasu” / “Odnośniki”, jeśli parser coś znajdzie.

## Testy

### Unit tests

- Katalog: `TyflocentrumTests/`
- Testy sieci (`TyfloAPI`) używają `StubURLProtocol` do stubowania `URLSession`.

### UI tests

- Katalog: `TyflocentrumUITests/`
- Aplikacja rozpoznaje argument launch `UI_TESTING` i wtedy:
  - używa in-memory Core Data (`DataController(inMemory: true)`),
  - stubuje sieć przez `UITestURLProtocol` (zdefiniowany w `Tyflocentrum/TyflocentrumApp.swift`).

Przydatne flagi launch (dla UI testów / debugowania):

- `UI_TESTING_FAIL_FIRST_REQUEST` – pierwsze requesty do wybranych endpointów zwrócą błąd (testowanie retry/pull-to-refresh).
- `UI_TESTING_TP_AVAILABLE` – symuluje aktywną audycję interaktywną (formularz kontaktu dostępny).

### Budowanie i testy z CLI (xcodebuild)

Przykładowe komendy (takie jak w CI) – nazwy symulatorów mogą się różnić między instalacjami Xcode:

```bash
# Testy na symulatorze (Unit + UI)
xcodebuild \
  -project Tyflocentrum.xcodeproj \
  -scheme Tyflocentrum \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -parallel-testing-enabled NO \
  -parallel-testing-worker-count 1 \
  test

# Archive bez code signing (pod unsigned IPA)
xcodebuild \
  -project Tyflocentrum.xcodeproj \
  -scheme Tyflocentrum \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/Tyflocentrum.xcarchive \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

## Dokumentacja w CI (guardrail)

Na PR-ach do `master` działa workflow `Docs (README) guard` (`.github/workflows/readme-guard.yml`), który wymaga aktualizacji `README.md` (lub dodania plików w `docs/`), jeśli zmieniasz m.in.:

- kod aplikacji (`Tyflocentrum/`),
- projekt Xcode / model danych (`Tyflocentrum.xcodeproj/`, `Tyflocentrum.xcdatamodeld/`),
- workflow CI (`.github/workflows/`),
- skrypty (`scripts/`).

Logika jest w `scripts/require-readme-update.sh`.

## Struktura repo

- `Tyflocentrum/` – kod aplikacji (Swift/SwiftUI).
- `TyflocentrumTests/` – testy jednostkowe.
- `TyflocentrumUITests/` – testy UI.
- `.github/workflows/` – CI (build + unsigned IPA).
- `scripts/` – narzędzia pomocnicze (np. pobieranie IPA z CI).
- `artifacts/` – katalog na pobrane / zbudowane artefakty (np. `tyflocentrum.ipa`).
- `installers/` – pliki pomocnicze (np. instalator iTunes dla Windows, przydatny w niektórych narzędziach do sideloadingu).

## Prywatność i bezpieczeństwo (praktycznie)

- Aplikacja pobiera treści z publicznych endpointów WordPress oraz stream audio.
- Pozycja odsłuchu jest zapisywana lokalnie w `UserDefaults`.
- Formularz kontaktu wysyła wpisane dane do endpointu Tyflopodcast (`kontakt.tyflopodcast.net`).
- W artykułach linki otwierają się w systemowej przeglądarce (`UIApplication.open`), a renderowanie HTML ma ograniczenia bezpieczeństwa (CSP + JS off).

## Dodatkowe materiały

- `CODE_REVIEW.md` – notatki z przeglądu kodu i propozycje usprawnień.
- `Tyflocentrum/readme.md` – krótka historia projektu (kontekst).
- `Tyflocentrum/Changelog.rtf` – changelog w formacie RTF (historycznie).

