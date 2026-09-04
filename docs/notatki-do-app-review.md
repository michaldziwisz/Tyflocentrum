# Notatki do App Review

Tekst do wklejenia w pole **App Review Information → Notes** w App Store Connect.
Trzymamy go w repo, bo przy każdej kolejnej wysyłce trzeba go tylko odświeżyć,
a nie pisać od zera.

Dlaczego to nie jest formalność: **najważniejsza funkcja aplikacji, czyli kontakt
z audycją, jest widoczna tylko wtedy, gdy trwa audycja interaktywna.** Recenzent
Apple, który trafi na aplikację w środku dnia, po prostu jej nie zobaczy i może
uznać, że funkcja nie istnieje albo że aplikacja jest niekompletna. Trzeba mu to
powiedzieć wprost, razem ze sposobem sprawdzenia.

---

## Treść notatki (wersja polska — do tłumaczenia na angielski przy wysyłce)

TyfloCentrum to oficjalny klient serwisów Tyflopodcast, Tyfloświat i Tyfloradio,
prowadzonych przez Fundację Instytut Rozwoju Regionalnego. Aplikacja jest
projektowana pod VoiceOver: użytkownikami są osoby niewidome i słabowidzące.

### Nie potrzeba konta ani logowania

Cała treść jest publiczna. Nie ma rejestracji, nie ma zakupów w aplikacji,
nie ma treści zablokowanej za jakimkolwiek warunkiem.

### Gdzie co jest

- **Nowości** — wspólna lista najnowszych podcastów i artykułów.
- **Podcasty** i **Artykuły** — te same treści w podziale na kategorie.
- **Szukaj** — wyszukiwanie w obu serwisach.
- **Tyfloradio** — odtwarzacz radia na żywo oraz ramówka.

Odtwarzacz podcastu otwiera się po wybraniu odcinka z listy. Obsługuje Magic Tap
(dwukrotne stuknięcie dwoma palcami przy włączonym VoiceOverze) do zatrzymania
i wznowienia odtwarzania.

### FUNKCJA ZALEŻNA OD CZASU: kontakt z audycją

Formularz kontaktu — wiadomość tekstowa oraz wiadomość głosowa — pojawia się
**tylko wtedy, gdy właśnie trwa audycja interaktywna** w Tyfloradiu. Aplikacja
pyta o to serwer (`tyflopodcast.net`, parametr `ac=current`) i pokazuje kontakt,
gdy serwer odpowie, że audycja jest na antenie. Poza godzinami audycji ta sekcja
jest niewidoczna i **to jest zachowanie zamierzone**, nie błąd.

Audycje na żywo są zwykle w godzinach wieczornych czasu polskiego (CET/CEST),
najczęściej we wtorki, środy i czwartki. Aktualna ramówka jest widoczna w zakładce
**Tyfloradio** oraz publicznie na `https://tyflopodcast.net`.

Jeśli recenzent trafi poza godzinami audycji i chce zobaczyć ten przepływ, prosimy
o kontakt pod adresem podanym jako Support URL — **podamy najbliższy konkretny
termin audycji**, wtedy funkcja będzie widoczna bez żadnych zmian w aplikacji ani
na serwerze.

**Nie włączamy trybu testowego audycji na żądanie i to jest świadoma decyzja.**
Ten sam serwer obsługuje aplikacje na Androida, Windows oraz stronę internetową,
a informacja „trwa audycja" dociera do wszystkich słuchaczy jednocześnie. Sztuczne
włączenie audycji na czas recenzji wprowadziłoby w błąd realnych użytkowników,
którzy zobaczyliby zaproszenie do kontaktu z audycją, której nie ma na antenie.
Wolimy podać termin niż zafałszować stan usługi.

### Mikrofon

Dostęp do mikrofonu służy wyłącznie do nagrania wiadomości głosowej do audycji.
Nagrywanie **zawsze inicjuje użytkownik**, przyciskiem na ekranie kontaktu.
Nagranie trafia do redakcji Tyfloradia i nie jest używane do niczego innego.
Aplikacja nie nagrywa w tle ani bez wyraźnego działania użytkownika.

### Powiadomienia push

W tej wersji są **wyłączone**. Kod obsługi istnieje, ale interfejs i rejestracja
są nieaktywne w buildzie Release — nie chcemy dostarczać funkcji pozornej.
Włączenie zaplanowane na kolejną wersję, wraz z aktualizacją „App Privacy".

### iPad

Aplikacja działa na iPhonie i iPadzie z tego samego kodu. Funkcje zależne od
czujników iPhone'a (zbliżenie, tak zwany „tryb ucha" przy nagrywaniu) są na
iPadzie ukryte i wyłączone, bo tam nie mają sensu.

### Treści i prawa

Podcasty, artykuły i strumień radia pochodzą z serwisów Fundacji Instytut Rozwoju
Regionalnego (Tyflopodcast, Tyfloświat, Tyfloradio). Aplikacja jest oficjalnym
klientem tych serwisów, tworzonym w porozumieniu z redakcją. Treść jest publicznie
dostępna również przez przeglądarkę.

### Dostępność

Aplikacja jest budowana pod czytnik ekranu i to jest jej główny powód istnienia.
Wszystkie elementy mają etykiety dla VoiceOvera, obsługiwane jest Dynamic Type,
a listy mają akcje dostępności. Jeśli w trakcie recenzji coś nie da się obsłużyć
z VoiceOverem, prosimy o zgłoszenie tego jako błędu — dla nas to defekt
krytyczny, nie kosmetyczny.

---

## Do uzupełnienia przed wysyłką

- [x] **Privacy Policy URL:** `https://michaldziwisz.github.io/Tyflocentrum/privacy/`
      (opublikowane i sprawdzone: kod 200, tytuł strony potwierdzony)
- [x] **Support URL:** `https://michaldziwisz.github.io/Tyflocentrum/`
      (ten sam adres podajemy wyżej jako kontakt na czas recenzji)
- [x] **wersja angielska: `docs/app-review-notes-en.md`** — to ona idzie do Apple,
      ta polska zostaje jako źródło i do naszego wglądu
- [x] **rozstrzygnięte: NIE włączamy trybu testowego audycji.** Ten sam serwer
      (`kontakt.tyflopodcast.net/json.php?ac=current`) obsługuje aplikacje na
      Androida i Windows oraz stronę, a flaga „trwa audycja" dociera do wszystkich
      słuchaczy naraz — sztuczne włączenie wprowadziłoby ich w błąd. Zamiast tego
      notatka podaje typowe dni audycji i obiecuje konkretny termin na życzenie
      recenzenta. Zapisane też w notatce po angielsku, żeby przy kolejnej wysyłce
      nikt nie „poprawił" tego z powrotem.
- [ ] sprawdzić spójność „App Privacy" w App Store Connect z `PrivacyInfo.xcprivacy`
      (rozbieżność między nimi jest częstym powodem odrzucenia)

Przy każdej kolejnej wysyłce aktualizuj **oba** pliki: ten i angielski. Rozjechanie
się ich znaczy, że wysyłamy Apple inną treść, niż mamy zapisaną u siebie.
