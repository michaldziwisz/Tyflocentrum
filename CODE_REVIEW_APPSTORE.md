# Tyflocentrum — code review + App Store readiness (iOS)

Data przeglądu: **2026-01-29**  
Stan repozytorium: `83bb751`  
Zakres: aplikacja iOS (`Tyflocentrum/`, `TyflocentrumTests/`, `TyflocentrumUITests/`) + komponent backendowy powiadomień (`push-service/`) w kontekście funkcji „push”.

## TL;DR (decyzje przed wysyłką do App Store)

### Najważniejsze ryzyka (w tej wersji)
1. **Powiadomienia push są niegotowe end‑to‑end**:
   - iOS: brak włączonej capability/entitlements dla APNs w projekcie (`Tyflocentrum.xcodeproj/project.pbxproj` nie zawiera konfiguracji push).
   - backend: `push-service/server.js` **nie wysyła** do APNs (tylko loguje fan‑out).
   - UI: sekcja „Powiadomienia push” jest widoczna w `Tyflocentrum/Views/SettingsView.swift`, domyślnie wszystko jest włączone → prompt o pozwolenie na powiadomienia może pojawić się na starcie.

   **Wniosek**: jeśli push ma być elementem tej wersji, to jest **blokada**. Jeśli push ma być „później”, rozważ ukrycie/wyłączenie UI push w buildzie App Store (żeby nie dostarczyć funkcji pozornej).

2. **Prywatność / App Store Connect**: musisz przygotować i podać **URL polityki prywatności** (wymóg w App Store Connect) oraz poprawnie wypełnić „App Privacy” (zbierane dane: podpis/imie, treść wiadomości, głosówka, token push/identyfikator instalacji).

3. **UX w Ustawieniach (push)**: w obecnym UI są techniczne statusy typu „Tryb rejestracji: ios-installation” i komunikat o braku Apple Developer Program — dla użytkowników końcowych może to wyglądać jak debug.

### Co jest mocne (duże plusy pod App Store i jakość)
- **Dostępność (VoiceOver)**: wiele `accessibilityLabel/Hint/Identifier`, sensowne akcje na wierszach list, Magic Tap (globalny i kontekstowy).
- **Audio**: przejście na `AVPlayer` + pilot systemowy (`MPRemoteCommandCenter`) + wznawianie + prędkość.
- **Bezpieczne renderowanie HTML**: `SafeHTMLView` bez JS, non‑persistent storage, kontrola nawigacji i schematów URL.
- **Testy**: unit tests + UI smoke tests z deterministycznym stubowaniem sieci (`StubURLProtocol`, `UITestURLProtocol`).

## 1) Dobre praktyki, architektura i utrzymanie

### Co jest dobrze zrobione
- **Wstrzykiwanie zależności i tryb UI testów**: `Tyflocentrum/TyflocentrumApp.swift` rozdziela konfigurację produkcyjną i testową (in‑memory Core Data, osobne `UserDefaults`, stub sieci).
- **Wyraźne warstwy „store”**: `FavoritesStore`, `SettingsStore`, `PushNotificationsManager` trzymają stan poza widokami i ograniczają „logikę w SwiftUI”.
- **Model audio**: `AudioPlayer` ma klarowny stan (co gra, czy live, czas/duration, rate) oraz sprzątanie observerów w `deinit`.
- **Lepsza odporność na awarie**: usunięcie `fatalError` z Core Data (`DataController`) — aplikacja nie wywraca się w runtime, tylko ma fallback.

### Rzeczy do dopracowania (bez zmiany „feature scope”, ale dla jakości kodu)
- **Spójność stylu i formatowania**: kilka plików ma niekonsekwentne wcięcia i układ (np. `Tyflocentrum/TyfloAPI.swift`, `Tyflocentrum/Views/DetailedPodcastView.swift`, `Tyflocentrum/VoiceMessageRecorder.swift`, testy). To nie blokuje releasu, ale utrudnia dalszy rozwój i review.
- **Martwy kod**: w repo są nieużywane/legacy komponenty HTML (`Tyflocentrum/Views/HTMLTextView.swift`, `Tyflocentrum/Views/HTMLRendererHelper.swift`). Warto usunąć, żeby nie mnożyć „fałszywych tropów”.
- **Konwencja nawigacji**: cały projekt wciąż używa `NavigationView` (iOS 17 preferuje `NavigationStack`). Nie jest to krytyczne, ale przy kolejnych iteracjach warto migrować.

## 2) Optymalizacja (wydajność i responsywność)

### Potencjalne hot‑spoty
- **HTML → plain text w modelach**: `Podcast.PodcastTitle.plainText` parsuje HTML przez `NSAttributedString` przy każdym odczycie. W listach (setki pozycji) to może kosztować CPU i powodować przycięcia.
  - Minimalna optymalizacja (bez zmiany funkcji): cache plain‑text na etapie mapowania do view‑state (np. w `WPPostSummary`/VM) albo memoizacja w modelu.
- **`cachePolicy = .reloadIgnoringLocalCacheData`** w większości requestów (`Tyflocentrum/TyfloAPI.swift`): wymusza brak cache i zwiększa koszt sieci + energii.
  - Jeśli celem jest „zawsze świeże”, OK; jeśli chcesz płynność/offline‑friendly, rozważ `URLCache` i cache w pamięci (np. na czas sesji) dla list.

### Co już wygląda sensownie
- Paginacja i ładowanie partiami w feedach (`NewsFeedViewModel`, `PagedFeedViewModel`) ograniczają jednorazowe „przebranie” 100+ elementów.
- `SafeHTMLView.optimizeHTMLBody` ogranicza koszt obrazków (lazy/async) bez JS.

## 3) Bezpieczeństwo

### Aplikacja iOS
- **Transport**: endpointy są HTTPS, brak widocznych ATS‑wyjątków w `Tyflocentrum/Info.plist` (dobrze).
- **HTML**: `SafeHTMLView`:
  - non‑persistent `WKWebsiteDataStore`,
  - JS wyłączony,
  - linki otwierane poza webview,
  - whitelist schematów (`http/https/mailto/tel`) i ograniczenie nawigacji głównej do hosta bazowego.
  To jest jeden z najważniejszych punktów „hardeningu” w tej aplikacji — duży plus.
- **Upload głosówki**: `Tyflocentrum/TyfloAPI.swift` buduje `multipart/form-data` w pliku tymczasowym i sprząta go `defer` (OK). `VoiceMessageRecorder` usuwa nagranie po wysłaniu/reset.

### Backend push (`push-service/`)
- Publiczne endpointy rejestracji tokenów są OK dla MVP, ale:
  - absolutnie wymagane jest **rate limiting** na reverse proxy,
  - konieczne jest zabezpieczenie pliku stanu (`state.json`) i katalogu danych (dostęp tylko serwis/administrator),
  - docelowo rozważ trzymanie tokenów w storage z lepszym modelem (DB) + rotacja/TTL.
- **Kluczowe**: brak wysyłki do APNs (obecnie tylko logi) → push nie działa.

## 4) Prywatność i dane użytkownika

### Jakie dane przetwarza aplikacja (praktycznie)
- **Kontakt z radiem**:
  - imię/podpis (`ContactViewModel.name`),
  - treść wiadomości tekstowej (`ContactViewModel.message`),
  - plik audio głosówki + metadane (czas trwania).
- **Powiadomienia push**:
  - token APNs (na urządzeniach) lub identyfikator instalacji (fallback),
  - preferencje kategorii powiadomień.
- **Lokalnie na urządzeniu**: ulubione i ustawienia (UserDefaults).

### Konsekwencje pod App Store
- W App Store Connect przygotuj:
  - **Privacy Policy URL** (wymóg) + spójny opis retencji i celu danych (kontakt z radiem, powiadomienia),
  - „App Privacy” (kategorie danych i ich cel).
- Rozważ, czy **rejestracja „installationID” na serwerze push** ma się dziać bez uzyskania zgody na powiadomienia i zanim użytkownik w ogóle wejdzie w ustawienia. To jest obszar ryzyka w kontekście zaufania i przejrzystości (nawet jeśli formalnie nie jest to tracking).

## 5) Testowalność i testy

### Co jest na plus
- Unit testy obejmują kluczowe elementy:
  - budowanie requestów i query (`TyflocentrumTests/TyfloAPITests.swift`),
  - `MultipartFormDataBuilder`,
  - modele i persystencję ustawień/ulubionych,
  - logikę feedów (paged/news),
  - aspekty audio session dla nagrywania.
- UI smoke testy mają sensowną strategię:
  - deterministyczne stubowanie sieci,
  - identyfikatory dostępności jako kontrakt testowy,
  - scenariusze awaryjne (stall/timeouts) i retry.

### Co bym dodał jako minimum „release confidence”
- Testy regresji dla:
  - `ShowNotesParser` (różne formaty znaczników czasu/linków),
  - `SafeHTMLView` (czy linki nie nawigują w webview, tylko otwierają zewnętrznie),
  - `PushNotificationsManager` (kiedy prosi o zgodę / kiedy rejestruje token / co robi po odmowie).

## 6) Dostępność (VoiceOver, Dynamic Type, ergonomia)

### Co jest bardzo dobre
- Konsekwentne `accessibilityIdentifier` (UI tests + debug).
- Akcje dostępności na wierszach (np. „Słuchaj”, „Skopiuj link”, „Ulubione”).
- Wsparcie **Magic Tap** globalnie + w ekranie głosówek (dobry UX dla VO).
- Player ma osobne opisy kontrolek i wartości (czas, prędkość).

### Rekomendacje (raczej „polish”, nie blokery)
- Dopracować copy/hinty tam, gdzie UI jest „techniczne” (szczególnie push).
- Na iPad rozważyć UX dla „trybu ucha” (to raczej funkcja „telefonowa”, a projekt targetuje iPad: `TARGETED_DEVICE_FAMILY = "1,2"`).

## 7) Wytyczne Apple / publikacja w App Store (checklista praktyczna)

Poniżej jest lista rzeczy, które realnie weryfikuje review (stabilność, kompletność, prywatność, uczciwość opisu) oraz elementy, które często blokują submission na etapie App Store Connect.

### 7.1 Minimalne wymagania „submission-ready”
- App nie może crashować i musi być testowalny bez „tajnych kroków” (wszystkie feature’y dostępne, backendy działają).
- Wypełnione pola w App Store Connect:
  - nazwa, opis, kategoria, wiek,
  - zrzuty ekranu (iPhone + iPad, jeśli wspierasz iPad),
  - **Support URL** i **Privacy Policy URL**,
  - „App Privacy” zgodne z realnym działaniem aplikacji.
- Export compliance (szyfrowanie): aplikacja używa HTTPS/TLS; w App Store Connect trzeba odpowiedzieć na pytania eksportowe. Jeśli nie używasz własnej kryptografii, zwykle kwalifikujesz się do wyjątku (warto też rozważyć ustawienie `ITSAppUsesNonExemptEncryption = NO`, jeśli to pasuje do Twojej sytuacji).

### 7.2 Punkty ryzyka specyficzne dla Tyflocentrum
#### Powiadomienia push
- Jeśli chcesz mieć push w tej wersji:
  - włącz capability **Push Notifications** dla bundle ID i dodaj entitlements,
  - backend musi faktycznie wysyłać do APNs,
  - dopracuj moment pytania o zgodę (niekoniecznie na starcie) + komunikaty w UI.
- Jeśli push ma być „wkrótce”:
  - lepiej nie pokazywać użytkownikom przełączników, które nic nie robią.

#### Mikrofon (głosówki)
- `NSMicrophoneUsageDescription` jest — super.
- Upewnij się, że w opisie aplikacji / notatkach do review jest jasne:
  - po co mikrofon,
  - że nagrywanie jest inicjowane wyłącznie przez użytkownika,
  - do kogo trafia głosówka i jaka jest retencja (to już część polityki prywatności).

#### Treści zewnętrzne (WordPress + radio)
- W opisie App Store i w notatkach do review warto zaznaczyć:
  - skąd pochodzą treści (Tyflopodcast/Tyfloswiat/Tyfloradio),
  - że masz prawa do używania nazwy i treści (albo jesteś oficjalnym klientem/partnerem).

### 7.3 Notatki do App Review (co im napisać)
- Krótki opis przepływów:
  - gdzie jest player,
  - gdzie jest kontakt (i że pojawia się tylko podczas audycji interaktywnej),
  - że aplikacja jest projektowana pod VoiceOver.
- Jeśli jakaś funkcja zależy od „czy trwa audycja” lub backendu (kontakt, ramówka), daj im informację jak to przetestować lub zapewnij stabilny tryb testowy na czas review.

## 8) Rekomendowana lista działań przed wysyłką (priorytety)

### Blokery (jeśli dotyczy)
- Push: zdecydować „w tej wersji tak/nie” i dopasować UI + backend + capabilities.
- App Store Connect: Privacy Policy URL + poprawne App Privacy (na podstawie realnych danych).

### Wysoki priorytet (polish pod stabilność i wizerunek)
- Usunąć/ukryć techniczne debug‑statusy w push UI (albo przepisać językiem użytkownika).
- Spiąć spójność formatowania (SwiftFormat / SwiftLint) i usunąć martwe pliki HTML helperów.

### Niski priorytet (po wydaniu 1.0)
- `NavigationStack` zamiast `NavigationView`.
- Cache (URLCache / in‑memory) dla list + optymalizacja HTML→plainText (memoizacja).

