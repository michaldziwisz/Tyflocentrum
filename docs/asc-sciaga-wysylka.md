# App Store Connect — ściąga wysyłkowa TyfloCentrum iOS

Ściąga do przejścia przez App Store Connect krok po kroku. Pisana pod obsługę
czytnikiem ekranu, z pułapkami dostępności zmierzonymi przy wydawaniu Sterigo
(lipiec 2026) — kilka elementów u Apple jest głuchych na klawiaturę i wiadomo
z góry, których to dotyczy.

**Zasada nadrzędna:** odpowiedzi w sekcji „App Privacy" **muszą** zgadzać się
z plikiem `Tyflocentrum/PrivacyInfo.xcprivacy` w repozytorium. Rozbieżność między
manifestem a odpowiedziami w sklepie to częsty powód odrzucenia — Apple porównuje
jedno z drugim automatycznie.

---

## Zanim zaczniesz: co jest już gotowe

| Rzecz | Stan | Gdzie |
|---|---|---|
| Team ID | `X2FN885LQU` | wpisane w projekt, pilnuje bramka `tools/test_konto_apple.py` |
| Bundle ID | `net.tyflocentrum.app` | wolny w App Store, sprawdzone |
| Nazwa | TyfloCentrum | wolna w App Store, sprawdzone |
| Polityka prywatności | opublikowana | `https://michaldziwisz.github.io/Tyflocentrum/privacy/` |
| Strona wsparcia | opublikowana | `https://michaldziwisz.github.io/Tyflocentrum/` |
| Notatki do recenzji (PL) | gotowe | `docs/notatki-do-app-review.md` |
| Notatki do recenzji (EN) | gotowe, **to wklejasz** | `docs/app-review-notes-en.md` |
| Klucz eksportowy | `ITSAppUsesNonExemptEncryption = false` | sprawdzone w `Info.plist`, więc pytania eksportowego **nie będzie** |
| Manifest prywatności | wdrożony | `Tyflocentrum/PrivacyInfo.xcprivacy` |
| Język aplikacji | `pl` | `developmentRegion = pl` w projekcie — VoiceOver będzie czytał po polsku |
| Orientacje ekranu | ustawione dla iPhone'a i iPada | w konfiguracji projektu, nie w `Info.plist` |
| Ikona | podpięta | `ASSETCATALOG_COMPILER_APPICON_NAME` ustawione, bramka `tools/test_ikony_ios.py` pilnuje rozmiarów i braku kanału alfa |

> Powyższe pozycje sprawdziłem w plikach, nie z pamięci. Przy Sterigo pierwszy
> upload odrzuciło **pięć** braków walidacji (ikona, jej powiązanie, nazwa klucza
> ikony, orientacje, wersja SDK) — tutaj orientacje, ikona i język są już na
> miejscu, więc te grabie mamy z drogi.

---

## KROK 1 — Zarejestruj App ID

Adres: `developer.apple.com/account/resources/identifiers/add/bundleId`

1. Wybierz **App IDs**, potem **App**.
2. **Description:** `TyfloCentrum` (to opis wewnętrzny, nie widzą go użytkownicy).
3. **Bundle ID:** wybierz **Explicit** i wpisz dokładnie `net.tyflocentrum.app`.
4. **Capabilities:** **nie zaznaczaj niczego.** Aplikacja nie używa żadnego
   entitlementu — push jest wyłączony, nie ma Hotspot ani iCloud. Zaznaczenie
   czegokolwiek „na zapas" może zepsuć podpis, bo profil musi zgadzać się
   z zawartością binarki.
5. **Continue**, potem **Register**.

> **Pułapka z Sterigo:** jeśli kiedyś podpisywałeś tę aplikację Sideloadly,
> na liście może już być wpis z doklejonym Team ID, czyli
> `net.tyflocentrum.app.X2FN885LQU`. **To nie jest nasz App ID** — potrzebujemy
> czystego `net.tyflocentrum.app`, bez sufiksu.

---

## KROK 2 — Utwórz rekord aplikacji

Adres: `appstoreconnect.apple.com/apps` → przycisk **+** → **New App**

1. **Platforms:** iOS.
2. **Name:** `TyfloCentrum` — to nazwa widoczna w App Store, maksymalnie 30 znaków.
3. **Primary Language:** **Polish**. To ważne: aplikacja jest po polsku i tak trzeba
   ją zgłosić, inaczej recenzent może uznać brak angielskiego za defekt.
4. **Bundle ID:** wybierz z listy `net.tyflocentrum.app` (pojawi się po kroku 1).
5. **SKU:** `tyflocentrum-ios` — dowolny identyfikator wewnętrzny, nigdzie nie widoczny.
6. **User Access:** Full Access.

---

## KROK 3 — App Privacy (najważniejszy krok)

Adres: rekord aplikacji → w menu po lewej **App Privacy**.

### 3a. Adresy

- **Privacy Policy URL:** `https://michaldziwisz.github.io/Tyflocentrum/privacy/`
- **User Privacy Choices URL:** zostaw puste (pole opcjonalne, nie mamy takiej strony).

### 3b. Pytanie wstępne

„Do you or your third-party partners collect data from this app?" → **Yes, we collect data from this app**.

> Dlaczego „tak", skoro nie ma analityki: Apple definiuje „collect" jako przesłanie
> danych poza urządzenie i przechowanie ich dłużej, niż trwa obsługa żądania.
> Wiadomość wysłana do redakcji spełnia tę definicję. Dane trzymane tylko na
> telefonie (ulubione, ustawienia) **nie są** zbieraniem i ich się nie deklaruje.

### 3c. Typy danych — zaznacz DOKŁADNIE trzy

Ekran pokazuje długą listę kategorii z podpunktami. Zaznacz tylko te trzy:

1. **Contact Info → Name**
2. **User Content → Audio Data**
3. **User Content → Other User Content**

Nic więcej. W szczególności **nie** zaznaczaj: Email Address, Phone Number,
Location, Identifiers, Usage Data, Diagnostics, Search History, Purchases.

> Te trzy pozycje odpowiadają jeden do jednego wpisom w `PrivacyInfo.xcprivacy`:
> `NSPrivacyCollectedDataTypeName`, `NSPrivacyCollectedDataTypeAudioData`,
> `NSPrivacyCollectedDataTypeOtherUserContent`.

### 3d. Szczegóły dla każdego z trzech typów

Apple zada dla każdego te same trzy pytania. Odpowiedzi są identyczne dla wszystkich trzech:

| Pytanie | Odpowiedź |
|---|---|
| How do you use this data? | **App Functionality** (i tylko to) |
| Is this data linked to the user's identity? | **No, this data is not linked to the user's identity** |
| Do you use this data for tracking purposes? | **No, we do not use this data for tracking purposes** |

Uzasadnienie, gdyby ktoś pytał: nie ma kont, więc nic nie da się powiązać
z tożsamością; nie ma reklam ani brokerów danych, więc nie ma śledzenia; dane
służą wyłącznie obsłudze kontaktu z audycją, czyli funkcji aplikacji.

### 3e. Zapisz

Przycisk **Publish** albo **Save** u góry. Te odpowiedzi można zmieniać później
bez wysyłania nowej wersji aplikacji.

---

## KROK 4 — Informacje o aplikacji

Adres: rekord aplikacji → **App Information**

- **Subtitle** (opcjonalny, do 30 znaków): `Tyflopodcast, Tyfloświat, radio`
- **Category → Primary:** **News**. Uzasadnienie: aplikacja daje dostęp do
  audycji i artykułów redakcyjnych, więc to najbliższa kategoria.
- **Category → Secondary:** opcjonalnie **Education**.
- **Content Rights:** zaznacz, że aplikacja zawiera treści osób trzecich i masz
  do nich prawa — jesteśmy oficjalnym klientem serwisów Fundacji.
- **Age Rating:** przejdź kwestionariusz, odpowiadając **None / No** na wszystko.
  Aplikacja nie ma przemocy, hazardu, treści dla dorosłych ani nieograniczonego
  dostępu do internetu. Wynik powinien wyjść **4+**.

---

## KROK 5 — Strona wersji (1.0)

Adres: rekord aplikacji → wersja **1.0 Prepare for Submission**

- **Promotional Text** (opcjonalny): można pominąć.
- **Description:** opis aplikacji po polsku. Propozycja gotowa do wklejenia jest
  niżej, w sekcji „Teksty do wklejenia".
- **Keywords:** `tyflopodcast,tyfloradio,tyfloświat,niewidomi,VoiceOver,dostępność,podcast,radio`
  (bez spacji po przecinkach — spacje zajmują limit 100 znaków).
- **Support URL:** `https://michaldziwisz.github.io/Tyflocentrum/`
- **Marketing URL:** to samo albo puste.
- **Screenshots:** wymagane dla iPhone 6,9" i, ponieważ wspieramy iPada, także dla
  iPada 13". Zrzuty generuje workflow **Zrzuty ekranu** w repozytorium — po jego
  uruchomieniu pobierz artefakt i wgraj pliki. Bramka `scripts/sprawdz_zrzuty.py`
  pilnuje, żeby rozmiary były zgodne z wymogami Apple.
- **App Review Information → Notes:** wklej **całą treść** z sekcji „Treść do
  wklejenia" w pliku `docs/app-review-notes-en.md`.
- **Sign-In Information:** **nie zaznaczaj** „Sign-in required" — nie mamy kont.
- **Version Release:** zalecam **Manually release this version**, żebyś sam
  decydował o momencie publikacji po zatwierdzeniu.

---

## KROK 6 — Build

Aplikację trzeba wysłać podpisaną. Z WSL zrobiliśmy to dla Sterigo bez Maca,
przez GitHub Actions — ta sama droga zadziała tutaj, ale wymaga jeszcze:

1. certyfikatu dystrybucyjnego (Apple Distribution),
2. profilu (App Store) dla `net.tyflocentrum.app`,
3. klucza App Store Connect API (plik `.p8`).

**To osobne zadanie i mogę je przygotować** — procedura jest opisana w skillu
`bse-hardware-iphone` i sprawdzona w praktyce. Powiedz słowo, a zrobię pipeline
analogiczny do Sterigo. Build z obecnego CI jest **niepodpisany**, więc do App
Store się nie nadaje.

Jedna rzecz jest już z drogi: nasz runner to `macos-26`, więc aplikacja zbuduje się
właściwym SDK. Przy Sterigo upload odrzuciło między innymi dlatego, że runner miał
za stare Xcode.

---

## Pułapki dostępności u Apple (zmierzone przy Sterigo)

Warto je znać z góry, bo wyglądają jak awaria konta, a są tylko wadą interfejsu.

1. **Filtr wyboru App ID przy tworzeniu profilu nie reaguje na Enter.** To nie lista
   rozwijana, a pole filtra z wynikami jako elementy klikalne myszą. Obejścia po kolei:
   zawęź filtr tak, by został jeden wynik; spróbuj **spacji** zamiast Enter; włącz
   tryb formularza NVDA i użyj spacji; symuluj klik myszą NVDA (na laptopie:
   `NVDA+Shift+M`, potem `NVDA+[`).
2. **Przełącznik zespołu pokazuje obie nazwy naraz** — to lista, nie dowód, że aktywny
   jest cudzy zespół. Rozstrzyga sekcja **Membership**: jeśli czyta „Individual",
   Twój telefon i Team `X2FN885LQU`, to jesteś u siebie i nie ma czego przełączać.
3. **Jeśli zespół faktycznie trzeba przełączyć**, a menu nie działa — wyloguj się
   całkowicie i zaloguj ponownie. Apple pokazuje wtedy **pełnoekranowy** wybór
   zespołu, który jest dostępny.
4. **Ekran DSA (trader / non-trader)** to ustawienie **konta**, nie tej aplikacji —
   przy Sterigo wybrałeś „trader", więc tu nic nie zmieniasz.

---

## Teksty do wklejenia

### Description (pole Description, po polsku)

```
TyfloCentrum daje dostęp do audycji Tyflopodcastu, artykułów Tyfloświata i radia
Tyfloradio — w jednym miejscu, bez zakładania konta.

Aplikacja jest tworzona z myślą o osobach niewidomych i słabowidzących. Obsługa
VoiceOverem nie jest dodatkiem, a punktem wyjścia: wszystkie elementy mają
etykiety, listy udostępniają akcje dostępności, a rozmiar tekstu podąża za
ustawieniami systemu.

Co możesz robić:
• słuchać najnowszych audycji i przeglądać je według kategorii,
• czytać artykuły Tyfloświata, w tym numery czasopisma,
• słuchać Tyfloradia na żywo i sprawdzać ramówkę,
• wyszukiwać w obu serwisach naraz,
• zapisywać ulubione audycje i artykuły,
• wracać do przerwanego odcinka od miejsca zatrzymania,
• zmieniać prędkość odtwarzania i korzystać ze znaczników czasu,
• wysyłać wiadomość tekstową lub głosową do audycji na żywo.

Odtwarzaniem sterujesz też Magic Tapem, czyli dwukrotnym stuknięciem dwoma
palcami przy włączonym VoiceOverze.

Aplikacja nie zawiera reklam, nie zbiera danych do celów marketingowych i nie
wymaga logowania. Treści pochodzą z serwisów Fundacji Instytut Rozwoju
Regionalnego.
```

### What's New in This Version (przy pierwszym wydaniu)

```
Pierwsze wydanie TyfloCentrum dla iPhone'a i iPada.
```

---

## Kolejność, gdybyś chciał ją mieć w jednym miejscu

1. Zarejestruj App ID (krok 1).
2. Utwórz rekord aplikacji (krok 2).
3. Wypełnij App Privacy (krok 3) — **najpilniejsze, bo blokuje wysyłkę**.
4. Uzupełnij App Information i Age Rating (krok 4).
5. Wypełnij stronę wersji 1.0, wklej notatki angielskie, wgraj zrzuty (krok 5).
6. Poproś mnie o pipeline podpisywania i wyślij build (krok 6).
7. **Submit for Review.**
