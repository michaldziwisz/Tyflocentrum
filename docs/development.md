# Tyflocentrum — development

## Repo layout

- `Tyflocentrum/` — kod aplikacji (Swift/SwiftUI)
- `TyflocentrumTests/` — unit tests
- `TyflocentrumUITests/` — UI tests + smoke
- `docs/` — dokumentacja (README jest celowo krótkie)
- `scripts/` — skrypty pomocnicze (np. pobieranie `.ipa` z CI)

## Najważniejsze entrypointy

- Start appki: `Tyflocentrum/TyflocentrumApp.swift`
  - konfiguruje zależności i wstrzykuje je przez `EnvironmentObject`,
  - hostuje `ContentView` w wrapperze obsługującym **Magic Tap** (VoiceOver).
- Taby: `Tyflocentrum/Views/ContentView.swift`

## Warstwy (w skrócie)

- UI: `Tyflocentrum/Views/*`
- Sieć / WordPress API + kontakt: `Tyflocentrum/TyfloAPI.swift`
- Audio (AVPlayer): `Tyflocentrum/AudioPlayer.swift`
- Bezpieczne renderowanie HTML: `Tyflocentrum/Views/SafeHTMLView.swift`
- Ulubione: `Tyflocentrum/FavoritesStore.swift`
- Ustawienia: `Tyflocentrum/SettingsStore.swift`

## Sieć i cache

- `TyfloAPI.fetch*` domyślnie używa `cachePolicy = .useProtocolCachePolicy` dla requestów do WordPress (listy/detale), żeby pozwolić `URLCache` obniżyć koszt sieci i energii (o ile serwery zwracają cache‑friendly nagłówki).
- Endpointy „na żywo” (`isTPAvailable`, `getRadioSchedule`) wymuszają `cachePolicy = .reloadIgnoringLocalCacheData` (żeby nie „przegapić” rozpoczęcia audycji / zmian w ramówce).

## Testy

### Unit tests

- `TyflocentrumTests/` (m.in. stubowanie `URLSession` przez `StubURLProtocol`).

### UI tests

- `TyflocentrumUITests/`
- App rozpoznaje argument launch `UI_TESTING` i wtedy:
  - używa in-memory Core Data,
  - stubuje sieć przez `UITestURLProtocol` (zdefiniowany w `Tyflocentrum/TyflocentrumApp.swift`).

Przykładowe flagi do scenariuszy awaryjnych:

- `UI_TESTING_FAIL_FIRST_REQUEST` — pierwsze requesty do wybranych endpointów zwrócą błąd (test retry/pull-to-refresh).
- `UI_TESTING_STALL_NEWS_REQUESTS` — symuluje “zawieszone” requesty w Nowościach.
- `UI_TESTING_STALL_DETAIL_REQUESTS` — symuluje “zawieszone” requesty detali (post/page).

### xcodebuild (jak w CI)

```bash
xcodebuild \
  -project Tyflocentrum.xcodeproj \
  -scheme Tyflocentrum \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -parallel-testing-enabled NO \
  -parallel-testing-worker-count 1 \
  test
```

## CI i artefakty

- Unsigned IPA: `.github/workflows/ios-unsigned-ipa.yml`
- Pobranie artifactu: `scripts/fetch-ipa.sh`

## Polityka dokumentacji (kompromis)

- `README.md` trzymamy **krótkie** (opis projektu + szybki start + linki).
- Szczegóły (funkcje, architektura, kontrakty, CI) trzymamy w `docs/`.
- Formatowanie kodu utrzymujemy spójne (docelowo można dołożyć SwiftFormat/SwiftLint, ale nie jest to blocker 1.0).
- Guard w CI (`scripts/require-readme-update.sh`) wymaga aktualizacji **README lub `docs/`** tylko wtedy, gdy zmiana dotyka “public surface” (nowe funkcje/API/CI/build), a nie przy każdej drobnej poprawce.
