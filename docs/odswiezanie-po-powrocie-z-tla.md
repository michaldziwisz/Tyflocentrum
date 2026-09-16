# Odświeżanie treści po powrocie aplikacji z tła

Dokumentuje naprawę zgłoszenia: „po zrzuceniu do app switchera i wywołaniu stamtąd
czasem nie dociąga nowych treści”.

## Co było nie tak

Aplikacja nie miała **żadnej** reakcji na powrót do pierwszego planu. W całym
projekcie nie występowało ani `scenePhase`, ani `willEnterForegroundNotification`,
ani `didBecomeActiveNotification`. `Info.plist` deklaruje tylko tryb `audio`, nie ma
`BGTaskScheduler` ani pushów z `content-available`, więc w tle nie działo się nic.

Powrót z app switchera nie odmontowuje widoków, dlatego `.task` na liście nie
uruchamiał się ponownie. A gdyby się uruchomił, strażnik `guard !hasLoaded` i tak
nic by nie pobrał, bo dane już były. Nowe treści dociągały się więc wyłącznie przy
**zimnym starcie** albo po ręcznym pull-to-refresh.

Stąd „czasem”: to nie była losowość aplikacji, a decyzja systemu, czy ubić proces
w tle. Ubił — zimny start i świeże treści. Proces przeżył — zero pobrania.

Do tego dwie usterki towarzyszące:

- **Ręczne odświeżenie mogło zwrócić stare dane.** `refresh()` szedł ścieżką
  `useProtocolCachePolicy`, a ta zawsze zaglądała do `NoStoreInMemoryCache` (TTL
  5 minut). Pull-to-refresh potrafił więc oddać zawartość pamięci.
- Serwisy nie wysyłają `ETag` ani `Last-Modified` (tyflopodcast.net nie wysyła też
  `Cache-Control`, tyfloswiat.pl wysyła `no-store`), więc rewalidacja warunkowa
  i odpowiedzi 304 nie istnieją.

## Jak to działa teraz

`StrategiaOdswiezania` (plik `Tyflocentrum/StrategiaOdswiezania.swift`) odpowiada na
jedno pytanie: czy wolno teraz sięgnąć do sieci. Reguła jest bezstanowa i czysta,
więc daje się sprawdzić testem bez uruchamiania interfejsu.

| powód | próg świeżości (120 s) | karencja po błędzie (30 s) |
|---|---|---|
| powrót z tła | obowiązuje | obowiązuje |
| wejście na zakładkę | obowiązuje | obowiązuje |
| żądanie użytkownika (pull-to-refresh) | pomijany | pomijany |

**Dlaczego dwa znaczniki czasu, a nie jeden.** Pierwsza wersja reguły patrzyła tylko
na wiek ostatniego *udanego* pobrania. Wygląda poprawnie i jest pułapką: przy martwej
sieci znacznik sukcesu nigdy się nie odświeża, więc **każdy** powrót do aplikacji
wystrzeliwałby kolejne żądanie dobijające do timeoutu. Reguła mająca chronić baterię
zamieniłaby słaby zasięg w pętlę nieudanych połączeń. Dlatego obok sukcesu notujemy
czas *próby* i po nieudanej odczekujemy `progPoBledzie`.

### Oszczędność baterii — pięć decyzji

1. **Zero pracy w tle.** Nie dodaliśmy `BGTaskScheduler`. Zużycie w tle pozostaje
   zerowe, a odświeżenie następuje wtedy, gdy użytkownik i tak trzyma telefon w ręku.
2. **Próg liczony od wieku danych**, nie od czasu spędzonego w tle — czas w tle nie
   obejmuje uśpienia urządzenia.
3. **Tylko widoczna zakładka.** `TabView` trzyma odwiedzone widoki zamontowane, więc
   bez bramki jedno przełączenie z app switchera uruchomiłoby pobranie we wszystkich
   odwiedzonych zakładkach naraz. Stąd `TabView(selection:)`, typ `ZakladkaAplikacji`
   i przekazanie aktywnej zakładki przez `@Environment(\.aktywnaZakladka)`.
4. **Tylko pierwsza strona.** Odtwarzanie całej paginacji przy każdym powrocie to
   kilkanaście żądań po to, żeby niemal zawsze dostać dane, które już mamy.
5. **Jedno żądanie naraz.** `trwaPobieranie` blokuje równoległe pobrania, a znacznik
   generacji (`requestGeneration`) pilnuje, żeby stare, zawieszone żądanie nie
   nadpisało nowszego wyniku.

### Zachowanie listy — nie ruszamy tego, co użytkownik czyta

`ScalanieNowosci` dokleja **wyłącznie** wpisy, których wcześniej nie było, i zostawia
resztę listy nietkniętą. Scalanie świadomie **nie sortuje całości od nowa**: pełne
przesortowanie mogłoby wstawić wpis w środek czytanej listy (artykuł datowany
wcześniej niż ostatnio wczytane pozycje), a to dla czytnika ekranu jest gorsze niż
brak nowości, bo element pod kursorem zmieniłby sąsiedztwo.

Pozycję trzyma `scrollPosition(id:)` w połączeniu z `scrollTargetLayout()` i stabilnym
`.id(item.id)` na każdym wierszu. Po scaleniu widok kotwiczy się na wpisie, który był
pierwszy **przed** doklejeniem, więc treść nie przesuwa się pod palcem.

Ogłoszenie dla VoiceOvera („3 nowe treści na górze listy”, z polską odmianą
liczebnika) leci **po** scaleniu i z opóźnieniem 1,2 s. W chwili powrotu do aplikacji
VoiceOver mówi swoje — nazwę aplikacji i element z fokusem — więc natychmiastowy
komunikat zostałby zagłuszony. Gdy nowych treści nie ma, nie ogłaszamy nic.

### Warstwa cache

Pierwsza strona listy pobierana jest z `reloadIgnoringLocalCacheData`, czyli z
pominięciem `URLCache` **i** własnego `NoStoreInMemoryCache`. Dalsze strony to
historia, która się nie zmienia, więc tam cache zostaje. `no-cache` nie jest przypięte
na stałe do zapytań: dopóki serwisy nie wysyłają walidatorów, cache i tak idzie do
sieci, a stały nagłówek zablokowałby tanie odpowiedzi 304, gdyby WordPress zaczął
kiedyś wysyłać `ETag`.

## Dowody

`TyflocentrumTests/StrategiaOdswiezaniaTests.swift` — 18 asercji, każda pozytywna ma
parę negatywną (świeże dane *nie* pobierają / stare pobierają; karencja blokuje /
po karencji przechodzi; brak nowości nie rusza listy / nowości lądują na górze).

Odpowiednik na Androidzie ma tę samą regułę i te same progi; tam zmierzono
20 testów, 0 błędów, 0 pominiętych, a kontrola ważności (cofnięcie karencji po
błędzie) wywala dokładnie 2 asercje.

## Czego ta naprawa NIE robi

Nie sprawdza nowych treści, gdy aplikacja jest w tle — świadomie, bo wymagałoby to
pracy w tle i kosztu baterii. Użytkownik dowiaduje się o nowościach po powrocie do
aplikacji albo z powiadomień push, które są osobnym mechanizmem.
