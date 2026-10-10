# Odświeżanie czasu bez restartu

## Zmiana

Ręczne odświeżenie listy przekazuje monotonnie rosnącą rewizję metadanych. Nie polega już wyłącznie na przejściu `isLoading`: SwiftUI może połączyć szybkie zmiany tej flagi w jednej aktualizacji, a ID i `modified_gmt` pozostają bez zmian po dopisaniu czasu na serwerze. Stan listy omija wtedy dodatni i ujemny cache, nie usuwa dobrych etykiet na czas transportu i odrzuca odpowiedzi starej generacji.

Nowości aktualizują także obiekty znanych ID podczas scalenia po powrocie z tła. Sama zmiana czasu nie jest nowym wpisem: nie powoduje komunikatu o nowościach ani zmiany kotwicy. Przy odświeżeniu znanych wpisów paginowane listy zachowują wiersze, kolejność, załadowany ogon i kursor dalszych stron. Stare doładowanie nie dopisuje danych po nowszym refresh. Kilka ręcznych żądań podczas pobierania łączy się w jedno najnowsze oczekujące żądanie.

Ulubione i spis treści numeru mają gest odświeżenia oraz dostępny przycisk „Odśwież”. Odświeżają opcjonalne metadane, nie przepisują zapisanych ulubionych ani całego numeru. Kategorie i wszystkie podcasty omijają cache pierwszej strony; wyszukiwanie ma jawne pominięcie cache. Odświeżenie istniejących wyników wyszukiwania nie ogłasza ponownie liczby wyników.

W `ScrollView` Nowości publikacja stanu podczas gestu potrafi anulować zadanie `refreshable`, mimo niezmienionej generacji i modelu. Osobny właściciel ekranu przechowuje pojedynczą operację, a gest czeka na jej wynik. Równoczesny gest dołącza do już trwającej pracy. Wyjście z ekranu, przełączenie zakładki i przejście do tła anulują ją jawnie. Model nadal odrzuca anulowane i spóźnione odpowiedzi; nie ma odłączonej pracy pozbawionej właściciela.

## Granice

Zachowane: porcje do 50 ID, cache do 512 pozycji, dodatni TTL 300 s, ujemny TTL 30 s, timeout metadanych 3 s, ważność danych tekstowych do 24 h oraz walidacja wersji/statusu/liczb/modified_gmt. Audio inline nie dostaje sztucznego `checked_at`.

Powrót z tła pyta ponownie dopiero po progu 120 s od danych albo po 30 s od nieudanej próby. Tylko widoczna powierzchnia obsługuje zdarzenie. Trwające pobranie metadanych nie jest anulowane samym szybkim przejściem fazy sceny. Nie ma cyklicznego odpytywania. Ręczna rewizja omija te progi, ale nie omija `Retry-After` dla 429/503. Dodatkowa zapora jest ograniczona do dwóch źródeł, obsługuje sekundy oraz datę HTTP, a brak/nierozpoznany nagłówek oznacza 30 s. Nie dodano automatycznych ponowień do klienta metadanych.

## Testy

- `testTimeRefreshOldFavoritesSameProcess`: podcast batch i tekst posts/pages zapisanych wcześniej ulubionych.
- Niezależne `testTimeRefreshNews/AllPodcasts/PodcastCategory/AllArticles/ArticleCategory/SearchSameProcess`: Nowości, wszystkie podcasty, kategoria podcastów, wszystkie artykuły, kategoria artykułów i wyszukiwanie. Porażka jednej listy nie ucina pozostałych.
- `testTimeRefreshMagazinePagesSameProcess`: artykuły numeru.
- Niezależne testy `testTimeResume…` wszystkich ośmiu powierzchni: rzeczywiste Home/activate bez launch/terminate, najpierw przed progiem, następnie po 121 s. Kontrolują PID. Osobny scenariusz przewija długą listę, porównuje prostokąt tego samego wiersza przed/po wznowieniu i wykonuje jego akcje.
- Każdy scenariusz ręczny: missing, ready, nowsze ready, powtórny gest bez zmiany danych, wycofane dane, błędne typy. Jawna kontrolka zmienia odpowiedź atrapy PRZED pojedynczym gestem; sama nie dotyka cache ani listy. W trybie odświeżania atrapa nie zmienia ID według liczby żądań.
- `NewsRefreshOperationTests`: anulowanie chwilowego zadania gestu, jawne anulowanie właściciela, spóźniony koniec po powrocie, współbieżne gesty oraz już anulowane wejście.
- `ContentTimeRefreshTests`: rewizje, próg wieku, ujemny cache, późny callback, anulowanie, Retry-After, 600 wpisów i ograniczony cache.
- `PagedFeedViewModelTests`: zachowanie wierszy podczas transportu, spóźniona paginacja, ręczne odświeżenie w trakcie pobierania oraz dotychczasowe testy przejęcia anulowanego ładowania.

Aparatura `UI_TESTING_TIME_PLAYBACK` generuje lokalny PCM WAV i przekazuje rzeczywisty AVPlayer do niezmienionego AudioPlayer. KVO liczy zmianę elementu i przejścia poza playing, obserwator czasu wykrywa cofnięcie. XCTest porównuje tożsamość elementu, postęp zegara i brak przerw podczas gestów oraz wznowienia przewiniętej listy. To pomiar silnika na symulatorze, nie odsłuch dźwięku z fizycznego iPhone.

Kontrolka serwera oraz logi TIME_ROW/TIME_STATE/TIME_REFRESH istnieją tylko w DEBUG z `UI_TESTING_TIME_REFRESH`. TIME_ROW zapisuje rzeczywisty tekst widoczny/dostępny i UUID stanu wiersza; TIME_STATE zapisuje tożsamość stanu i klienta. Nie dodają zastępczego elementu AX z kopią etykiety. XCTest odczytuje istniejący wiersz, sprawdza czas dokładnie raz i zapisuje jego nazwę oraz zrzut ekranu. Wynik symulatora nie potwierdza mowy ani fokusu fizycznego VoiceOver.

## Powtórzenie lokalne bez nadpisania dowodów

Z katalogu repozytorium, do nowego katalogu poza repo:

    python3 tools/test_content_time_refresh.py --out /absolutny/nowy-katalog/model --zapisz
    python3 tools/test_time_refresh_xctest.py --out /absolutny/nowy-katalog/xctest-linux --zapisz
    python3 tools/test_content_time_list.py --out /absolutny/nowy-katalog/list-600 --zapisz

`test_content_time_refresh.py --source /absolutny/katalog-bazy` wykonuje te same asercje na wskazanym drzewie źródeł. Dwa pierwsze narzędzia odmawiają nadpisania istniejącego katalogu wynikowego. Sonda stanu i modele używają wyciętych, niezmienionych deklaracji aplikacji, ale adapterów otoczenia zamiast SwiftUI i API listy. To nie jest test UI.

Pełny odbiór wymaga `bash scripts/build-unsigned-ipa.sh` na macOS z Xcode 26: lint, bramki Python, XCTest jednostkowy i UI, archiwum Release. Surowy xcresult trzeba zachować również przy sukcesie. Workflow TestFlight i numer wersji nie są częścią tej poprawki.
