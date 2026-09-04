# Podpisywanie i wysyłka iOS bez Maca

Ta instrukcja domyka **krok 6** ze ściągi `docs/asc-sciaga-wysylka.md`. Procedura
jest sprawdzona w praktyce przy Sterigo — cały podpisany build i wysyłka robią się
na runnerze GitHuba, bez fizycznego Maca.

## Co jest gotowe, a co wymaga Ciebie

Uczciwie na wstępie: **tego kroku nie da się zrobić w całości bez Ciebie.** Trzy
rzeczy powstają wyłącznie po zalogowaniu na konto Apple i nikt inny ich nie wygeneruje.

| Rzecz | Kto robi | Stan |
|---|---|---|
| Klucz prywatny + wniosek o certyfikat (CSR) | ja, lokalnie | **zrobione** |
| Workflow wysyłkowy `ios-testflight.yml` | ja | **zrobione** |
| Certyfikat dystrybucyjny (`.cer`) | **Ty** (portal Apple) | czeka |
| Profil App Store (`.mobileprovision`) | **Ty** (portal Apple) | czeka |
| Klucz App Store Connect API (`.p8`) | **Ty** (App Store Connect) | czeka |
| Przetworzenie plików i 7 sekretów w GitHubie | ja | czeka na pliki od Ciebie |

Dlaczego nie mogę tego obejść: certyfikat i klucz API to **dane uwierzytelniające
Twojego konta Apple**. Portal wymaga zalogowania i akceptacji regulaminu przez
człowieka — nie ma publicznego API do ich tworzenia. To bariera z założenia.

Dobra wiadomość: **klucz prywatny nigdy nie opuszcza naszej maszyny.** Ty wgrywasz
tylko wniosek (CSR), a Apple oddaje certyfikat pasujący do klucza, który został u nas.

---

## KROK A — Certyfikat dystrybucyjny (Ty)

Plik wniosku czeka gotowy w:
`C:\Users\m\Downloads\tyflocentrum-signing\dist.csr`

1. Wejdź na `developer.apple.com/account/resources/certificates/add`
2. Wybierz **Apple Distribution**, potem **Continue**.
3. W polu wyboru pliku wskaż `dist.csr` z katalogu powyżej.
4. **Continue**, potem **Download** — zapisz `distribution.cer` **do tego samego
   katalogu** `Downloads\tyflocentrum-signing\`.

> Nie potrzebujesz Maca ani programu Keychain Access. Klucz prywatny mam lokalnie,
> więc certyfikat i klucz połączę w paczkę `.p12` po swojej stronie.

## KROK B — Profil App Store (Ty)

1. `developer.apple.com/account/resources/profiles/add`
2. W sekcji **Distribution** wybierz **App Store Connect** (albo „App Store" —
   nazwa zależy od wersji strony), potem **Continue**.
3. **App ID:** wskaż `net.tyflocentrum.app`.
   > **Pułapka dostępności zmierzona przy Sterigo:** to nie lista rozwijana, a pole
   > filtra z wynikami klikalnymi myszą — **Enter często nic nie robi**. Obejścia po
   > kolei: wpisz `TyfloCentrum`, żeby został jeden wynik; spróbuj **spacji** zamiast
   > Enter; włącz tryb formularza NVDA i użyj spacji; symuluj klik myszą NVDA
   > (na laptopie `NVDA+Shift+M`, potem `NVDA+[`).
4. **Certificate:** zaznacz certyfikat utworzony w kroku A.
5. **Provisioning Profile Name:** wpisz dokładnie **`TyfloCentrum App Store`**.
   > Ta nazwa jest zaszyta w workflow. Inna nazwa = build nie znajdzie profilu.
6. **Generate**, potem **Download** — zapisz `.mobileprovision` do tego samego katalogu.

## KROK C — Klucz App Store Connect API (Ty)

1. `appstoreconnect.apple.com` → **Users and Access** → zakładka **Integrations**
   → **App Store Connect API**
2. Przycisk **+** (Generate API Key). Nazwa: `TyfloCentrum CI`, rola **App Manager**.
3. **Zapisz sobie Key ID i Issuer ID** — możesz mi je podać zwykłym tekstem, nie są
   tajne bez pliku klucza.
4. Pobierz plik `AuthKey_XXXXXXXX.p8` do tego samego katalogu.
   > **Ten plik można pobrać tylko RAZ.** Jeśli go zgubisz, trzeba wygenerować nowy klucz.

## KROK D — Reszta (ja)

Gdy powiesz, że pliki są w katalogu, robię wszystko pozostałe bez Twojego udziału:

1. weryfikuję, że certyfikat pasuje do klucza prywatnego (porównanie modułów) —
   niezgodność wychodzi tu, a nie przy budowaniu,
2. składam paczkę `.p12` z losowym hasłem,
3. sprawdzam profil: właściwy App ID, brak `get-task-allow`, brak listy urządzeń,
4. tworzę środowisko `release` w repozytorium, ograniczone do gałęzi domyślnej,
5. wpisuję **7 sekretów** przez `gh` (mam uprawnienia, sprawdzone),
6. odpalam workflow i pilnuję wyniku.

### Siedem sekretów, które ustawię

| Nazwa | Skąd |
|---|---|
| `APPLE_DIST_CERT_P12_BASE64` | paczka `.p12`, którą złożę |
| `APPLE_DIST_CERT_PASSWORD` | losowe hasło, które wygeneruję |
| `APPLE_PROVISIONING_PROFILE_BASE64` | plik z kroku B |
| `APPLE_TEAM_ID` | `X2FN885LQU` (już wiadomo) |
| `ASC_KEY_ID` | z kroku C |
| `ASC_ISSUER_ID` | z kroku C |
| `ASC_API_KEY_P8_BASE64` | plik `.p8` z kroku C |

---

## Co robi workflow

Kolejność jest celowa — każdy krok, który może paść, pada **przed** kosztownym budowaniem:

1. **sprawdza, czy wszystkie 7 sekretów istnieje** i wypisuje brakujące po nazwie,
2. wybiera Xcode 26, więc SDK będzie akceptowane przez Apple,
3. importuje certyfikat do **tymczasowego** keychainu, który znika z maszyną,
4. instaluje profil i **weryfikuje go**: App ID musi być `net.tyflocentrum.app`,
   a `get-task-allow` musi być `false`, inaczej przerywa,
5. archiwizuje z podpisem i eksportuje `.ipa` metodą `app-store`,
6. **waliduje** paczkę przed wysłaniem, potem wysyła do App Store Connect,
7. zachowuje `.ipa` jako artefakt, także gdy coś padnie.

Uruchamia się **tylko ręcznie**, z gałęzi domyślnej, po wpisaniu `tak` w polu
potwierdzenia. Wysyłka do Apple jest skutkiem publicznym i nie ma się dziać
przy zwykłym pushu.

## Czego workflow NIE robi

Po udanej wysyłce build **nie jest** automatycznie zgłoszony do recenzji. Przy
Sterigo była to realna pułapka: build siedział w stanie „gotowy do zgłoszenia",
a wyglądało, jakby poszedł dalej. Zgłoszenie wersji do recenzji robi się w App
Store Connect przyciskiem **Submit for Review** — albo mogę to domknąć przez API,
jeśli poprosisz.

## Pułapki zapisane, żeby nie wracały

- **Wersja buildu musi rosnąć.** Apple odrzuci powtórzony numer. Przed kolejną
  wysyłką podnosimy `CURRENT_PROJECT_VERSION`.
- **`mkdir` w tym samym kroku co zapis pliku.** Przy Sterigo osobny, późniejszy
  krok `mkdir` wywalił workflow, bo YAML wykonuje kroki po kolei.
- **Paczka `.p12` z opcją `-legacy`.** Nowszy OpenSSL tworzy format, którego
  keychain macOS nie zawsze czyta.
- **Ostrzeżenia `brew tap-trust` i o Node 20 to nie błędy** — pojawiają się
  w każdym naszym przebiegu i nie mają wpływu na wynik.
