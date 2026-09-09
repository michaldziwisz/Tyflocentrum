# Odpowiedź na odrzucenie 1.0 — Guideline 2.1, Information Needed

Apple odrzucił wersję 1.0 (zgłoszenie `da969dcd-12b8-4fc0-8107-fd6e966954a0`,
stan `UNRESOLVED_ISSUES`, wersja `REJECTED`) z **Guideline 2.1 – Information
Needed – New App Submission**. Uzasadnienie: *„submitted by a developer account
that has a limited App Review history”*.

## Co to znaczy, a czego NIE znaczy

To **nie jest zarzut do aplikacji ani do metadanych**. Apple nie wskazał żadnego
defektu, żadnej wytycznej treściowej i żadnego braku w karcie sklepu. Jest to
standardowa procedura dla konta bez historii recenzji: żądanie dowodu, że
aplikacja działa i że wiadomo, kto ją dostarcza.

Konsekwencja praktyczna, ważna dla planowania: **nie ma tu nic do naprawiania
w kodzie**. Nie podnosimy `CURRENT_PROJECT_VERSION`, nie budujemy nowego builda,
nie wysyłamy nowej wersji. Build 1 (`edccbda0`) zostaje ten sam — Apple pyta
o informacje, nie o poprawkę.

Odwrotny błąd byłby kosztowny: przy odrzuceniu odruch podpowiada „zmień coś
i wyślij ponownie”, a nowy build zaczyna recenzję od zera i nie odpowiada na
pytanie, które zadano.

## Czego API NIE zrobi (zmierzone na specyfikacji, nie założone)

Specyfikacja ASC API 4.4.1 (966 ścieżek) **nie ma ani jednego endpointu do
korespondencji z recenzentem** — brak ścieżek `resolution`, `correspondence`,
`thread`, `reply`. Odpowiedź w Resolution Center wkleja człowiek w przeglądarce.

Programowo da się zrobić dwie rzeczy i obie robimy:

- `PATCH /v1/appStoreReviewDetails/{id}` — pole Notes (Apple wprost prosi, żeby
  te informacje **także** tam wpisać, „for reference on future submissions”),
- `POST /v1/appStoreReviewAttachments` — załącznik z nagraniem ekranu.

## Blokada, którą trzeba było zdjąć pierwszą: nagranie z fizycznego urządzenia

Apple żąda nagrania ekranu z **fizycznego** urządzenia, zaczynającego się od
uruchomienia aplikacji. Żeby takie nagranie mogło powstać, aplikacja musi być na
telefonie — a bez Maca jedyną drogą jest TestFlight. **TestFlight był pusty**
(zero grup beta), czyli żądanie Apple było niewykonalne, dopóki tego nie
naprawiliśmy.

`tools/testflight_wewnetrzny.py` zakłada grupę **wewnętrzną**:

```bash
python3 tools/testflight_wewnetrzny.py --pokaz     # diagnoza, nic nie zmienia
python3 tools/testflight_wewnetrzny.py --zapisz
```

Dlaczego wewnętrzna, a nie zewnętrzna: grupa wewnętrzna przyjmuje wyłącznie
użytkowników App Store Connect i **nie przechodzi Beta App Review**, więc build
jest do zainstalowania od razu. Grupa zewnętrzna oznaczałaby kolejne czekanie na
Apple — czyli tę samą blokadę, tylko przesuniętą.

Link publiczny jest jawnie wyłączony (`publicLinkEnabled: false`): wersja, która
nie przeszła recenzji App Store, nie ma trafiać do osób z zewnątrz.

Stan po zmianie, potwierdzony odczytem: grupa
`ee7203f3-b70a-47fe-8222-0e6aa15476ea`, tester `michal@dziwisz.net` (`INVITED`),
build `edccbda0` przypięty.

## Kurtyna ekranu VoiceOver zepsuje nagranie — i to jest niewidoczne dla autora

Przy włączonej kurtynie ekranu nagranie wychodzi **czarne**. Autor tej aplikacji
jest niewidomy, więc nie zauważy tego przy odtwarzaniu; Apple odrzuci nagranie
po raz drugi, tym razem za nieczytelny materiał.

Przed nagrywaniem: potrójne stuknięcie trzema palcami (kurtyna wyłączona),
jasność w górę. Mowy VoiceOvera **nie trzeba** łapać mikrofonem — iOS przechwytuje
wyjście audio VoiceOvera wprost do nagrania ekranu, więc mikrofon zostaw
wyłączony (mniej szumu, brak przypadkowego tła).

## Funkcja, której recenzent nie mógł zobaczyć

Kontakt z audycją pojawia się **tylko podczas trwającej audycji interaktywnej**
(`ac=current`); poza tym oknem przycisk pokazuje komunikat „Na antenie Tyfloradia
nie trwa teraz żadna audycja interaktywna”. To najprawdopodobniejsza przyczyna,
dla której zgłoszenie wyglądało na niekompletne.

Dlatego nagranie ma sens **wyłącznie w trakcie audycji**. Sprawdzenie okna:

```bash
curl -s "https://kontakt.tyflopodcast.net/?ac=current" | grep -o '<h1>.*</h1>'
# "Trwająca audycja: <nazwa>" = okno otwarte
```

Nie włączamy flagi audycji sztucznie: ten sam serwer obsługuje Androida, Windows
i stronę, a informacja „trwa audycja” dociera do wszystkich słuchaczy naraz.

## Prawo do treści (punkt 6 listy Apple) — potwierdzone u źródła

Apple pyta o dokumenty na materiał osób trzecich. Podcasty, artykuły i strumień
należą do serwisów Fundacji Instytut Rozwoju Regionalnego, więc twierdzenie
„działamy w porozumieniu z redakcją” wymagało dowodu, a nie zapewnienia.

Dwa niezależne, publicznie weryfikowalne źródła:

| fakt | źródło |
|---|---|
| **redaktor naczelny** Tyflopodcastu, zarazem pomysłodawca projektu | `https://tyflopodcast.net/autorzy/michaldziwisz/` |
| **redaktor** TyfloŚwiata (obok Michała Kasperczaka), adres w domenie `firr.org.pl` | stopka `https://tyfloswiat.pl` |

To jest silniejsza odpowiedź niż licencja, bo dostawcą aplikacji jest osoba
**prowadząca redakcję** tych serwisów. Do tego wszystkie nagrania Tyflopodcastu
są publikowane na licencji Creative Commons BY 3.0 PL (stopka serwisu).

W odpowiedzi podajemy linki, nie skany. Recenzent może je sprawdzić sam, a my nie
wysyłamy dokumentów, o które nikt nie prosił.

## Guideline 1.2 — komentarze: ryzyko na NASTĘPNĄ recenzję, nie na tę

Apple tego nie podniósł, ale aplikacja **wyświetla** komentarze użytkowników
(`PodcastCommentsView`, tylko do czytania — dodawania w tej wersji nie ma).
Guideline 1.2 wymaga w aplikacjach z treścią użytkowników mechanizmu zgłaszania
nadużyć i blokowania autorów.

Stan faktyczny do obrony w tej wersji: komentarze są moderowane przez redakcję
**przed** publikacją, aplikacja ich nie tworzy i nie przyjmuje, a te same treści
są publicznie dostępne w przeglądarce.

**Michał chce w przyszłości dodać pisanie komentarzy z aplikacji.** To zmienia
rachunek i dlatego notuję to tutaj, a nie „na marginesie”: w chwili, gdy
aplikacja zacznie **przyjmować** treść od użytkowników, obrona „my tylko
wyświetlamy” przestaje działać, a Guideline 1.2 staje się twardym wymogiem
wydania. Potrzebne będą wtedy trzy rzeczy naraz:

1. mechanizm zgłaszania obraźliwej treści,
2. mechanizm blokowania autorów,
3. zobowiązanie do usunięcia zgłoszonej treści i wyrzucenia autora w ciągu 24 h.

Wniosek praktyczny: pisanie komentarzy **nie jest samą funkcją wysyłania POST-a**
— to funkcja plus komplet moderacyjny. Warto to wiedzieć przed zaplanowaniem
wersji, a nie po odrzuceniu.

Osobna pułapka na to samo wydanie: dopisanie wysyłki komentarzy zmienia też
odpowiedzi w App Privacy (pojawia się „User Content” powiązany z użytkownikiem),
a rozbieżność App Privacy z faktycznym działaniem jest częstym powodem
odrzucenia.

## Kolejność pracy

1. Nagranie ekranu w trakcie audycji (człowiek, iPhone).
2. `tools/odpowiedz_na_odrzucenie.py --zapisz` — Notes + załącznik przez API.
3. Wklejenie odpowiedzi w Resolution Center (człowiek, przeglądarka) — API tego
   nie umie.
4. Ponowne zgłoszenie tej samej wersji, bez nowego builda.
