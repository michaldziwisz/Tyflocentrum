# Tyflocentrum — development

## Repo layout

- `Tyflocentrum/` — kod aplikacji (Swift/SwiftUI)
- `TyflocentrumTests/` — unit tests
- `TyflocentrumUITests/` — UI tests + smoke
- `docs/` — dokumentacja (README jest celowo krótkie)
- `scripts/` — skrypty pomocnicze (np. pobieranie `.ipa` z CI)

## CI (build IPA)

- Unsigned IPA: `.github/workflows/ios-unsigned-ipa.yml` (GitHub-hosted **`macos-26`**)
  - lint: `swiftformat --lint` (wersja **przypięta**, patrz niżej)
  - test: `xcodebuild test` (Simulator)
  - build: artifact `Tyflocentrum-unsigned-ipa` (`tyflocentrum.ipa`)
- Skrypt używany przez workflow: `scripts/build-unsigned-ipa.sh`
- Pobranie artifactu: `scripts/fetch-ipa.sh` (albo UI GitHub Actions)
- Diagnostyka powtarzalności testów: `.github/workflows/diagnostyka-testu.yml`
  (uruchamia wskazane testy N razy; przydatne przy testach wrażliwych na czas)

### Dlaczego `macos-26`, a nie `macos-latest` ani `macos-14`

Dwa powody, oba twarde:

1. Apple wymaga od **28.04.2026**, by aplikacje wysyłane do App Store Connect
   były budowane **Xcode 26 na SDK iOS 26**. Build na starszym SDK nie nadaje
   się do wydania, choćby był zielony.
2. Kod używa symboli z nowszego SDK (`AVAudioSession.CategoryOptions.allowBluetoothHFP`,
   `AVAssetExportSession.export(to:as:)`), więc na Xcode 15.4 (`macos-14`) nie
   kompilował się wcale. Obraz `macos-14` jest też oznaczony jako wycofywany.

Wersję obrazu przypinamy **jawnie**: `macos-latest` wędruje i sam zmieniłby SDK
w trakcie życia projektu — czyli ta sama klasa błędu, co nieprzypięty SwiftFormat.

### Dlaczego wersja SwiftFormat jest przypięta (i sprawdzana)

Lint to zgodność z **konkretnym wydaniem** narzędzia, nie test poprawności kodu.
Kolejne wydania SwiftFormat dodają reguły, więc niezmieniony plik zaczyna oblewać
lint sam z siebie. Tak zczerwieniało to CI między styczniem a marcem 2026: skrypt
brał narzędzie przez `brew install` (zawsze najnowsze) i przebiegi padały po
13 sekundach, więc build ani testy się nie uruchamiały. Pomiar na tym repo:
wersja `0.58.7` → 1 plik z 63 do formatowania, wersja `0.63.0` → 22 z 63.

Dlatego `scripts/build-unsigned-ipa.sh` pobiera dokładnie wersję z
`SWIFTFORMAT_VERSION` i **przerywa pracę**, gdy `swiftformat --version` zwróci
inną — samo przypięcie bez kontroli jest deklaracją, nie mechanizmem.
Workflow `SwiftFormat` czyta tę samą wersję ze skryptu lintu, żeby nie
przeformatował repo nowszym narzędziem i nie wypchnął tego na `master`.

Dowód: `scripts/test-bramka-wersji-swiftformat.sh` (7 asercji, z kontrolą
negatywną: podstawiona binarka podająca inną wersję musi obalić bramkę).

## Prywatność i wymogi App Store

- **`Tyflocentrum/PrivacyInfo.xcprivacy`** — manifest prywatności. Apple nie
  przyjmuje aplikacji używających „required reason API” bez deklaracji.
  Zadeklarowane kategorie wynikają ze skanu kodu: `UserDefaults` (`CA92.1`) oraz
  metadane plików w `VoiceMessageRecorder` (`C617.1`).
  Manifest **musi być w fazie Resources** targetu — plik tylko na dysku nie
  trafia do builda, więc App Store by go nie zobaczył.
- **`ITSAppUsesNonExemptEncryption = false`** w `Info.plist` — aplikacja używa
  wyłącznie HTTPS/TLS systemu, bez własnej kryptografii.
- Dowód: `tools/test_manifest_prywatnosci.py` (15 asercji). Porównuje manifest
  z kodem **w obie strony**: brak deklaracji oznacza odrzucenie wysyłki,
  a deklaracja „na zapas” to nieprawdziwe oświadczenie wobec Apple.

## Ikona aplikacji

Ikona jest wspólna dla wersji Windows, Android i iOS. Nie edytuj plików PNG
ręcznie — generuje je `tools/generuj_ikone_ios.py` z `tools/symbol_zrodlowy.png`:

```bash
python3 tools/generuj_ikone_ios.py            # podglad, nic nie zapisuje
python3 tools/generuj_ikone_ios.py --zapisz   # zapis do Assets.xcassets
python3 tools/test_ikony_ios.py               # 11 asercji
python3 tools/test_ikony_ios.py --kontrola-waznosci
```

Czym iOS różni się od Androida (nie jest to ten sam problem geometryczny):

- **bez kanału alfa** — App Store odrzuca ikony z przezroczystością,
- **bez własnych zaokrągleń** — iOS sam nakłada maskę squircle; własny narożnik
  dałby zaokrąglenie podwójne, z ciemną obwódką,
- **bez strefy bezpiecznej 66/108** znanej z adaptive icon Androida, więc symbol
  ma pełne 75% szerokości kafla, jak w oryginale z Windows.

Test pilnuje też **kontrastu symbolu do tła** wg WCAG 1.4.11 (obecnie 8,12:1
przy progu 3:1). To nie jest ozdobnik: ikona o niskim kontraście jest realną
barierą dla osób słabowidzących, a autor projektu jest niewidomy i nie sprawdzi
tego wzrokiem.

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

## UI i dostępność (VoiceOver)

- Widok **Nowości** używa `ScrollView + LazyVStack` zamiast `List`, bo na niektórych urządzeniach `List` nie wystawia przewidywalnie systemowego paska przewijania VoiceOver na pierwszym ekranie (pojawiał się dopiero po kilku gestach przewijania).

## Sieć i cache

- `TyfloAPI.fetch*` domyślnie używa `cachePolicy = .useProtocolCachePolicy` dla requestów do WordPress (listy/detale), żeby pozwolić `URLCache` obniżyć koszt sieci i energii (o ile serwery zwracają cache‑friendly nagłówki).
- Dla odpowiedzi z `cache-control: no-store` (np. część endpointów TyfloŚwiata) TyfloAPI ma dodatkowy **in-memory cache z TTL = 5 min** (żeby ograniczyć powtarzane requesty i drenaż baterii).
- Endpointy „na żywo” (`isTPAvailable`, `getRadioSchedule`) wymuszają `cachePolicy = .reloadIgnoringLocalCacheData` (żeby nie „przegapić” rozpoczęcia audycji / zmian w ramówce).

## Testy

### Unit tests

- `TyflocentrumTests/` (m.in. stubowanie `URLSession` przez `StubURLProtocol`).

## Formatowanie (SwiftFormat)

- Konfiguracja: `.swiftformat` (repo root).
- CI: workflow `iOS (unsigned IPA)` uruchamia `swiftformat --lint` przed testami.
- **Wersja jest przypięta** w `scripts/build-unsigned-ipa.sh` (`SWIFTFORMAT_VERSION`)
  i sprawdzana — powody w sekcji „Dlaczego wersja SwiftFormat jest przypięta”.
- Lokalnie na macOS (użyj TEJ SAMEJ wersji, co CI, inaczej dostaniesz inny wynik):

```bash
WERSJA="$(grep -oE 'SWIFTFORMAT_VERSION:-[0-9.]+' scripts/build-unsigned-ipa.sh | head -1 | cut -d- -f2-)"
brew install swiftformat        # UWAGA: daje najnowsza, sprawdz `swiftformat --version`
swiftformat --config .swiftformat .
```

- Bez Maca, wprost w WSL/Linuksie — wydania SwiftFormat mają binarkę linuksową,
  więc lint da się sprawdzić bez runnera macOS i bez zużywania minut CI:

```bash
WERSJA="$(grep -oE 'SWIFTFORMAT_VERSION:-[0-9.]+' scripts/build-unsigned-ipa.sh | head -1 | cut -d- -f2-)"
curl -fsSL -o /tmp/sf.zip \
  "https://github.com/nicklockwood/SwiftFormat/releases/download/$WERSJA/swiftformat_linux.zip"
unzip -o /tmp/sf.zip -d /tmp/sf && chmod +x /tmp/sf/swiftformat_linux
/tmp/sf/swiftformat_linux --config .swiftformat --lint .
```

- Automatyczna poprawa bez Maca: uruchom workflow GitHub Actions **SwiftFormat**
  (manual). Jeśli są zmiany, workflow sam je zacommituje do `master`.

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
- Formatowanie kodu utrzymujemy spójne przez **SwiftFormat** (lint w CI + manual workflow do automatycznej poprawy).
- Guard w CI (`scripts/require-readme-update.sh`) wymaga aktualizacji **README lub `docs/`** tylko wtedy, gdy zmiana dotyka “public surface” (nowe funkcje/API/CI/build), a nie przy każdej drobnej poprawce.
