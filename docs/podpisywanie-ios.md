# Podpisywanie i wysyłka iOS bez Maca

Ta instrukcja domyka **krok 6** ze ściągi `docs/asc-sciaga-wysylka.md`. Cały podpisany
build i wysyłka robią się na runnerze GitHuba, bez fizycznego Maca.

## Co jest gotowe, a co wymaga Ciebie

Rzeczy, które kiedyś trzeba było klikać w portalu Apple, powstają teraz przez
App Store Connect API. Zostaje **jedna** czynność w przeglądarce: klucz API.

| Rzecz | Kto robi | Jak |
|---|---|---|
| Klucz prywatny + wniosek o certyfikat (CSR) | my, lokalnie | `openssl`, klucz nie opuszcza maszyny |
| Klucz App Store Connect API (`.p8`) | **Ty**, raz | `appstoreconnect.apple.com` → Users and Access → Integrations |
| App ID (bundle ID) | my | `POST /v1/bundleIds` |
| Certyfikat dystrybucyjny | my | `POST /v1/certificates` z naszym CSR |
| Profil App Store | my | `POST /v1/profiles`, typ `IOS_APP_STORE` |
| 7 sekretów w GitHubie | my | `tools/przygotuj_podpisywanie.py` |
| Rekord aplikacji w App Store Connect | **Ty**, raz | API tego nie umie, patrz niżej |
| Sekcja App Privacy | **Ty**, raz | API tego nie umie, patrz niżej |

### Czego App Store Connect API NIE umie

Zmierzone na oficjalnej specyfikacji OpenAPI 4.4.1 (966 ścieżek), nie założone:

- **utworzenie rekordu aplikacji** — `/v1/apps` ma wyłącznie `GET`. Apple pisze
  wprost, żeby nowych aplikacji nie tworzyć przez API;
- **App Privacy** (deklaracje zbierania danych) — w specyfikacji nie istnieje
  żaden endpoint dla tych odpowiedzi. Jest tylko `accessibilityDeclarations`,
  czyli etykiety dostępności, co to zupełnie inna rzecz.

Wszystko pozostałe — metadane wersji, kategoria wiekowa, zrzuty ekranu, cena,
dostępność terytorialna, wysyłka buildu i **Submit for Review** — jest dostępne
programowo.

## KROK A — klucz App Store Connect API (Ty, jednorazowo)

1. `appstoreconnect.apple.com` → **Users and Access** → **Integrations** →
   **App Store Connect API** → **Team Keys**.
2. Jeśli widzisz **Request Access**, najpierw to (wymaga roli Account Holder).
3. **+**, nazwa np. `TyfloCentrum CI`.
4. Rola: **Admin**. To nie jest ostrożność na zapas — klucz **App Managera nie ma
   dostępu do Certificates, Identifiers & Profiles**, więc nie wystawi certyfikatu
   ani profilu i wracamy do klikania w portalu.
5. **Generate**, potem od razu **Download API Key**. Plik `AuthKey_XXXXXXXXXX.p8`
   pobiera się **tylko raz**; zgubiony = trzeba wygenerować nowy klucz.
6. Plik ląduje w `~/tyflocentrum-signing/`, Issuer ID (UUID ze strony) podajesz
   zwykłym tekstem. Key ID odczytujemy z nazwy pliku.

## KROK B — App ID, certyfikat i profil (my, jedno polecenie)

```bash
python3 tools/wystaw_podpisywanie.py --pokaz     # diagnoza, nic nie tworzy
python3 tools/wystaw_podpisywanie.py --zapisz    # tworzy brakujące
```

Narzędzie jest **idempotentne**: każdy krok najpierw sprawdza, czy rzecz już
istnieje. Certyfikat rozpoznaje przez **porównanie klucza publicznego** z naszym
CSR, nie po nazwie — ta sama osoba może mieć kilka certyfikatów, a tylko jeden
pasuje do klucza prywatnego, który mamy.

Zapisuje `distribution.cer` i `TyfloCentrum.mobileprovision` do
`~/tyflocentrum-signing/`.

## KROK C — sekrety w GitHubie (my)

```bash
python3 tools/przygotuj_podpisywanie.py --katalog ~/tyflocentrum-signing \
    --issuer-id <ISSUER_ID>
```

Przed ustawieniem czegokolwiek sprawdza, po kolei od najtańszego błędu: czy
certyfikat **pasuje do naszego klucza prywatnego** (porównanie modułów), czy jest
typu Apple Distribution, czy Team ID się zgadza, czy profil dotyczy właściwego
App ID, czy nie jest deweloperski (`get-task-allow` musi być `false`) i czy nie ma
listy urządzeń.

Siedem sekretów ląduje w środowisku `release`, ograniczonym do gałęzi `master`:
`APPLE_DIST_CERT_P12_BASE64`, `APPLE_DIST_CERT_PASSWORD`,
`APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`.

## KROK D — rekord aplikacji (Ty, jednorazowo)

`appstoreconnect.apple.com/apps` → **+** → **New App**:

- **Platforms:** iOS
- **Name:** `TyfloCentrum`
- **Primary Language:** Polish
- **Bundle ID:** `net.tyflopodcast.tyflocentrum` (jest już zarejestrowany, więc
  będzie na liście)
- **SKU:** `tyflocentrum-ios`
- **User Access:** Full Access

## KROK E — build i wysyłka (my)

```bash
gh workflow run ios-testflight.yml -R michaldziwisz/Tyflocentrum \
    --ref master -f potwierdzam=tak
```

Kolejność kroków workflow jest celowa — każdy, który może paść, pada **przed**
kosztownym budowaniem: sprawdzenie 7 sekretów, wybór Xcode 26, import certyfikatu
do **tymczasowego** keychainu, instalacja i **weryfikacja** profilu, archiwum
z podpisem, eksport metodą `app-store`, walidacja paczki, wysyłka, a na końcu
`.ipa` jako artefakt (także przy porażce).

Uruchamia się tylko ręcznie, z gałęzi domyślnej, po wpisaniu `tak` — wysyłka do
Apple jest skutkiem publicznym i nie ma się dziać przy zwykłym pushu.

## Bundle ID: dlaczego NIE `net.tyflocentrum.app`

Upstream miał `net.tyflocentrum.app` i tak było w projekcie. **Apple odmawia
rejestracji tego identyfikatora:** `POST /v1/bundleIds` zwraca HTTP 409,
„An App ID with Identifier 'net.tyflocentrum.app' is not available". Identyfikator
jest zajęty poza naszym kontem (w koncie go nie ma, w App Store nie ma aplikacji,
która by go używała), a takiej blokady nie da się zdjąć przez API ani samodzielnie
w portalu — zwolnić go może wyłącznie wsparcie Apple.

Kontrola negatywna, żeby nie oskarżyć mechanizmu zamiast identyfikatora:
`net.tyflocentrum.probaXK7` i `net.tyflocentrum.app.X2FN885LQU` zarejestrowały się
tym samym wywołaniem bez problemu (oba potem usunięte). Czyli blokada dotyczy
dokładnie tego jednego łańcucha, nie prefiksu i nie naszych uprawnień.

Wybraliśmy `net.tyflopodcast.tyflocentrum` — **ten sam identyfikator, co wydanie
na Google Play**, więc aplikacja ma jedną nazwę pakietu na obu platformach.
Pilnuje tego bramka `tools/test_konto_apple.py`: sprawdza, że bundle ID jest nasz
**oraz** że zajęty identyfikator z upstreamu nie wrócił (merge z upstreamu dotyka
`project.pbxproj`, więc powrót jest realny i byłby cichy — build podpisałby się
profilem, którego nie mamy).

## Pułapki zapisane, żeby nie wracały

- **Wersja buildu musi rosnąć.** Apple odrzuci powtórzony numer. Przed kolejną
  wysyłką podnosimy `CURRENT_PROJECT_VERSION`.
- **`mkdir` w tym samym kroku co zapis pliku.** Osobny, późniejszy krok `mkdir`
  wywalił kiedyś workflow, bo YAML wykonuje kroki po kolei.
- **Paczka `.p12` z opcją `-legacy`.** Nowszy OpenSSL tworzy format, którego
  keychain macOS nie zawsze czyta.
- **Nie sklejaj stdout ze stderr, gdy czytasz DANE.** `openssl smime -verify`
  wypakowuje profil na stdout, a równolegle pisze „Verification successful" na
  stderr. Zlepienie obu strumieni dokleja ten napis do binarnego plist i
  `plistlib` przerywa błędem „junk after document element" — poprawny profil
  wygląda wtedy na uszkodzony. Stąd `uruchom_dane()` obok `uruchom()`.
- **Ostrzeżenia `brew tap-trust` i o Node 20 to nie błędy** — pojawiają się
  w każdym przebiegu i nie mają wpływu na wynik.
