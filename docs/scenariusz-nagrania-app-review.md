# Scenariusz nagrania ekranu dla App Review (Guideline 2.1)

Nagranie z **fizycznego iPhone'a**, żądane przez Apple przy odrzuceniu 1.0.
Aplikację bierzesz z TestFlight (grupa „Wewnetrzni (nagrania i testy)”).

Każdy ekran opisany niżej został sprawdzony w kodzie, nie odtworzony z pamięci —
napisy w cudzysłowach to dokładne etykiety z widoków.

## ZANIM WŁĄCZYSZ NAGRYWANIE

1. **Wyłącz kurtynę ekranu**: potrójne stuknięcie trzema palcami. Przy włączonej
   kurtynie film wyjdzie CZARNY, a tego nie da się sprawdzić słuchem — Apple
   odrzuci nagranie po raz drugi.
2. **Jasność w górę.**
3. **Mikrofon w Centrum sterowania zostaw WYŁĄCZONY.** Mowa VoiceOvera nagrywa
   się sama (iOS przechwytuje wyjście audio), a mikrofon dołożyłby tylko szum
   pokoju. Jeśli chcesz komentować głosem — wtedy włącz, ale mowa VoiceOvera i tak
   będzie słyszalna.
4. **Sprawdź, czy trwa audycja** — bez tego punkt 8 jest niewykonalny:
   ```bash
   curl -s "https://kontakt.tyflopodcast.net/?ac=current" | grep -o '<h1>.*</h1>'
   ```
   Ma zwrócić „Trwająca audycja: …”.
5. Zamknij aplikację całkowicie (przesuń w górę z przełącznika aplikacji), żeby
   nagranie pokazało **pełny start**, nie powrót do otwartego ekranu.

Start nagrywania: Centrum sterowania → Nagrywanie ekranu → 3 sekundy odliczania.

## CO NAGRAĆ, PO KOLEI

Apple wymaga, żeby film **zaczynał się od uruchomienia aplikacji** i pokazywał
typowy przepływ użytkownika. Kolejność poniżej jest tym przepływem.

### 1. Uruchomienie (obowiązkowe jako pierwsze)

Ekran główny telefonu → stuknij ikonę **TyfloCentrum** → poczekaj na wczytanie
listy. Niech widać, że aplikacja startuje od zera.

### 2. Nowości — główna lista treści

Zakładka **„Nowości”**. Przewiń kilka pozycji palcem (albo przesunięciami
VoiceOvera). To wspólna lista najnowszych podcastów i artykułów — pokaż, że są tu
oba rodzaje treści.

### 3. Odtwarzanie odcinka + Magic Tap

Wybierz odcinek z listy → otworzy się odtwarzacz → uruchom odtwarzanie, niech
dźwięk poleci **kilka sekund**. Potem:

- **Magic Tap**: dwukrotne stuknięcie dwoma palcami → pauza,
- ponownie Magic Tap → wznowienie.

To jest funkcja dostępnościowa, o której warto, żeby recenzent wiedział.
Wróć wstecz.

### 4. Podcasty i Artykuły — treść po kategoriach

Zakładka **„Podcasty”** → wejdź w jedną kategorię → pokaż listę odcinków → wstecz.
Zakładka **„Artykuły”** → wejdź w jedną kategorię → otwórz jeden artykuł, żeby
widać było wyrenderowany tekst → wstecz.

### 5. Komentarze do odcinka (WAŻNE, patrz uwaga niżej)

Wejdź w szczegóły dowolnego odcinka i otwórz **„Komentarze”**. Wybierz jeden
komentarz, żeby pokazać jego treść.

**Dlaczego to musi być na filmie:** aplikacja wyświetla treść pochodzącą od
użytkowników, a Apple sprawdza to pod Guideline 1.2. Ukrycie tego byłoby gorsze
niż pokazanie — film ma udowodnić, że **nie ma tu żadnego pola do pisania**,
czyli że aplikacja treści użytkowników nie przyjmuje. Nagranie jest dowodem na
naszą korzyść, nie ryzykiem.

### 6. Szukaj

Zakładka **„Szukaj”** → wpisz jakieś słowo (np. „NVDA”) → pokaż wyniki. Szuka
w obu serwisach naraz.

### 7. Tyfloradio — strumień na żywo i ramówka

Zakładka **„Tyfloradio”**:

- **„Posłuchaj Tyfloradia”** → strumień na żywo, niech pogra kilka sekund → wstecz,
- **„Sprawdź ramówkę”** → pokaż ramówkę → wstecz.

### 8. NAJWAŻNIEJSZE: kontakt z audycją (tylko w trakcie audycji)

To ta funkcja, której recenzent najprawdopodobniej **nie zobaczył** i dlatego
zgłoszenie wyglądało na niekompletne.

Zakładka **„Tyfloradio”** → przycisk **„Skontaktuj się z Tyfloradiem”**.
Aplikacja pyta serwer, czy trwa audycja. Poza godzinami audycji wyskoczyłby
komunikat „Na antenie Tyfloradia nie trwa teraz żadna audycja interaktywna” —
w trakcie audycji otworzy się ekran **„Kontakt”** z dwiema pozycjami:

**a) „Napisz wiadomość tekstową”**
- wpisz coś w pole **„Imię”**,
- wpisz coś w pole wiadomości,
- pokaż, że przycisk **„Wyślij wiadomość”** stał się aktywny.
- Wysłać możesz, ale nie musisz. Jeśli wyślesz, trafi to do redakcji na antenie —
  Ty decydujesz. Samo pokazanie działających pól wystarcza.
- Wstecz.

**b) „Nagraj wiadomość głosową”**
- ekran **„Głosówka”**,
- naciśnij przycisk nagrywania (albo Magic Tap), powiedz kilka słów, zatrzymaj,
- pokaż **„Odsłuchaj”** i długość nagrania,
- pokaż **„Usuń nagranie”** — czyli że użytkownik ma nad tym kontrolę.
- Tu również wysyłka jest opcjonalna.

To jest jedyne miejsce, gdzie aplikacja używa mikrofonu, i zawsze na wyraźne
działanie użytkownika. Warto, żeby to było widać.

### 9. Menu: Ulubione i Ustawienia

Przycisk **„Menu”** (trzy poziome linie, dostępny z każdego widoku):

- **„Ulubione”** → jeśli masz coś dodane, pokaż listę; jeśli nie, wystarczy sam ekran,
- **„Ustawienia”** → pokaż „Pozycja” (etykieta rodzaju treści) i „Tryb”
  (zapamiętywanie prędkości odtwarzania).

**Nie szukaj tu sekcji powiadomień push** — jest schowana za `#if DEBUG`, więc
w buildzie z TestFlight (Release) jej nie ma. To zgodne z tym, co piszemy Apple:
push jest w tej wersji wyłączony.

### 10. Zakończenie

Wróć na ekran główny aplikacji i zatrzymaj nagrywanie.

## CZEGO NIE MA I NIE SZUKAJ

Apple wymienia w liście rzeczy, których w tej aplikacji **nie ma** — nie da się
ich nagrać i tak też odpowiadamy:

- rejestracja, logowanie, usuwanie konta — **nie ma kont wcale**,
- treść płatna, zakupy w aplikacji — **nie ma**,
- tworzenie treści przez użytkownika — komentarze są tylko do czytania (patrz p. 5).

## DŁUGOŚĆ I FORMAT

3–6 minut. Nie spiesz się: recenzent ma zobaczyć, że aplikacja działa, a nie
zgadywać, co się stało na ekranie. Film zapisze się w Zdjęciach (Kolekcje →
Rodzaje mediów → Nagrania ekranu).

Gdy będzie gotowy, podaj mi ścieżkę do pliku (przez Taildrop na Windows albo
kabel) — załącznik do App Review wgram przez API, a resztę odpowiedzi złożę.
