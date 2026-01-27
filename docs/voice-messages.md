# Wysyłanie wiadomości głosowych do TyfloRadia (plan)

## Goal
- Dodać w Tyflocentrum możliwość nagrania **głosówki** i wysłania jej do panelu kontaktowego TyfloRadia.
- Głosówka ma działać **tylko w trakcie audycji** (gdy panel jest „aktywny”), wymagać **podpisu** i umożliwiać **odsłuch przed wysyłką**.
- Po stronie panelu kontaktowego:
  - głosówki mają być **widoczne i odsłuchiwalne tylko dla admina**,
  - mają dawać się usuwać pojedynczo (jak komentarze) oraz przy zakończeniu audycji,
  - mają mieć standardowy odtwarzacz HTML5 (play/pause, scrub, download).
- Zmiany muszą być **additive** (brak regresji dla istniejących endpointów i innych aplikacji korzystających z panelu).

## Assumptions / constraints
- Maks. długość nagrania: **20 minut**.
- Brak rate-limitu (na razie).
- Limit rozmiaru: przyjmujemy **50 MB** jako twardą granicę po stronie serwera (zgodnie z ograniczeniami/proxy po drodze).
- Jakość: **mono OK**, ale bitrate nie „bardzo niski” (cel: emisja w radiu).
- iOS wyśle `duration` (klientowa), ale serwer policzy `duration` po swojej stronie i to będzie wartość kanoniczna.
- Format pliku audio:
  - iOS: nagranie jako **AAC w kontenerze M4A** (najprostsze i sensowna jakość/rozmiar),
  - panel admina: odtwarzanie w HTML5 `<audio>`; dla maksymalnej kompatybilności między Chrome/Firefox przewidzieć **fallback „Pobierz plik”** (w razie braku dekodera w przeglądarce/OS).

## Research (current state)
- Panel kontaktowy: `/mnt/d/projekty/kontakt/`
  - `json.php` obsługuje `ac=current|add|del|create|dispose|list|schedule|setschedule`.
  - `functions.php` trzyma dane w pliku `._tp.dat` jako `TPData` z listą `TPComment` (serializacja PHP).
  - Admin: uwierzytelnienie przez `?pwd=...` → sesja `tp_session` → `isAdmin()`.
  - `admin.js` odświeża `ac=list` i renderuje listę komentarzy; usuwa po indeksie.
- iOS:
  - `Tyflocentrum/Views/ContactView.swift` – formularz „Kontakt” (imię + wiadomość).
  - `Tyflocentrum/TyfloAPI.swift` – `contactRadio()` wysyła JSON do `https://kontakt.tyflopodcast.net/json.php?ac=add`.

## Analysis
### Options (backend)
1) **Rozszerzyć istniejący model komentarzy** (TPComment) o „rodzaj” (`text` / `voice`) + metadane audio; dodać nowe akcje w `json.php`.
2) Trzymać głosówki w osobnym store (oddzielny plik + oddzielne endpointy listujące).

### Options (liczenie długości serwer-side)
A) `ffprobe` (jeśli dostępny na serwerze) – szybkie i dokładne, ale wymaga binarki/`exec`.
B) Biblioteka PHP (np. getID3) – działa bez binarek, ale dodaje zależność do repo.
C) Zaufać wartości z iOS – najprostsze, ale mniej wiarygodne.

### Decision
- Backend: **Opcja 1** (rozszerzenie `TPComment` + nowe akcje) – najmniej inwazyjne, zero zmian w istniejących akcjach, proste sprzątanie przy `del/dispose`.
- Długość: serwer liczy i zapisuje jako kanoniczną; iOS wysyła `duration` jako „hint” / fallback.
  - Wybrane: **getID3** (biblioteka PHP; brak zależności od środowiska).
  - Fallback: jeżeli getID3 nie policzy (np. nietypowy plik) → użyć wartości z iOS + twardy limit 20 min.
- Format: kanonicznie przechowujemy **M4A (AAC)**; endpoint `ac=voice` zwraca poprawny `Content-Type` (np. `audio/mp4`) + „download” link w panelu jako fallback.

### Risks / edge cases
- Upload i limity PHP/serwera (`post_max_size`, `upload_max_filesize`, timeouty); konieczne walidacje + czytelny błąd.
- Bezpieczeństwo uploadu: walidacja MIME/rozszerzenia, losowa nazwa pliku, brak path traversal, brak ekspozycji publicznej URL.
- Zgodność serializacji (PHP 8.2): unikać dynamicznych pól – dopisać właściwości do klasy `TPComment`.
- `ac=list` jest publiczne: trzeba **filtrować głosówki dla nie-admina**, żeby nie wyciekały.
- Sprzątanie plików: przy `del` i `dispose` usuwać pliki audio powiązane z komentarzami typu `voice`.

## Q&A (answered)
- iOS wysyła duration: **tak**.
- Rate limit: **nie** (na razie).
- Dokument: **w repo Tyflocentrum** (ten plik).
- Długość serwer-side: **tak** (kanoniczna po stronie serwera).
- Sposób liczenia serwer-side: **biblioteka PHP (getID3)**.
- Wymóg kompatybilności odtwarzania w panelu: **Chrome + Firefox** (fallback pobrania pliku, jeśli dekoder nie jest dostępny).

## Implementation plan
### 1) Backend: `/mnt/d/projekty/kontakt`
1) Dodać storage na audio (np. `TP_VOICE_DIR`) i funkcje pomocnicze:
   - zapisywanie uploadu (bez trzymania całego pliku w pamięci),
   - walidacja rozmiaru (<= 50 MB) i typu (np. m4a/aac),
   - liczenie `duration_ms` przez **getID3** i limit 20 minut (<= 1_200_000 ms),
   - jeżeli getID3 nie policzy: fallback do `duration_ms` z iOS (jeśli przesłane) + nadal limit 20 min.
2) Rozszerzyć `TPComment` o pola (przykład):
   - `public $kind` (`text`/`voice`)
   - `public $voiceFile` (np. nazwa pliku / ścieżka względna)
   - `public $voiceMime`
   - `public $durationMs`
   - (opcjonalnie) `public $originalFilename`
3) Nowe akcje w `json.php` (additive):
   - `ac=addvoice`:
     - `multipart/form-data`: `author`, `duration_ms`, `audio` (plik).
     - jeśli nie trwa audycja → błąd.
     - zapisuje plik + dodaje komentarz typu `voice`.
   - `ac=voice&id=<index>`:
     - **admin-only** (wymaga `isAdmin()`),
     - streamuje bytes pliku audio z poprawnymi nagłówkami (`Content-Type`, `Content-Length`, `Cache-Control: no-store`).
4) Zmiana `ac=list`:
   - dla nie-admina: zwraca tylko `text` (jak dotychczas).
   - dla admina: zwraca również `voice` (z dodatkowymi polami).
5) Zmiany `del` i `dispose`:
   - jeśli usuwany komentarz ma `kind=voice` → usuń plik audio.
   - `dispose`: usuń wszystkie pliki audio (jeżeli są).
6) Admin UI (`admin.js`):
   - jeśli element ma `kind=voice` → renderuj `<audio controls>` wskazujący na `json.php?ac=voice&id=...`,
   - pokaż podpis + czas + długość,
   - zachować istniejące „Usuń”.

### 2) iOS: Tyflocentrum
1) UI w `ContactView`:
   - sekcja „Wiadomość tekstowa” (bez zmian),
   - sekcja „Wiadomość głosowa”:
     - przyciski: `Nagraj` / `Zatrzymaj` / `Odsłuchaj` / `Usuń nagranie` / `Wyślij głosówkę`,
     - stan i komunikaty VO: czas nagrania, limit 20 min, błąd uprawnień.
2) Nagrywanie:
   - `AVAudioRecorder` do `.m4a` (AAC-LC), mono, np. 44.1kHz, bitrate ~128–192 kbps.
   - `AVAudioSession` `.playAndRecord` + obsługa route changes/interruption.
   - `NSMicrophoneUsageDescription` w `Info.plist`.
3) Upload:
   - `multipart/form-data` do `json.php?ac=addvoice`.
   - pola: `author`, `duration_ms`, `audio` (plik).
   - error handling: czytelny komunikat (VO) + retry.
4) Testy (iOS):
   - testy unit dla budowania requestu multipart (boundary, pola, MIME),
   - testy logiki stanu recorder/upload (z protokołem `VoiceRecorder` i fejkową implementacją dla testów),
   - testy UI: czy w trybie bez mikrofonu pokazujemy sensowny błąd (bez realnego nagrywania w CI).

## Tests to run (po wdrożeniu)
- iOS: `xcodebuild test` (unit + UI smoke).
- Backend (manual smoke):
  - `curl` multipart do `ac=addvoice` (podczas aktywnej audycji),
  - admin: `ac=list` pokazuje `voice`, `ac=voice&id=...` zwraca audio,
  - `ac=del` usuwa plik, `ac=dispose` sprząta wszystko.
