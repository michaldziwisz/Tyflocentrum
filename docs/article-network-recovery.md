# Pobieranie artykułów i stron Tyfloświata

## Polityka

`fetchArticle` i `fetchTyfloswiatPage` korzystają ze wspólnego przepływu pobierania szczegółów. Dotychczasowa polityka list i podcastów pozostaje bez zmian.

Budżet całej operacji wynosi 30 sekund, pojedynczej próby 12 sekund. W testach z `UI_TESTING_FAST_TIMEOUTS` próba trwa najwyżej 2 sekundy. Druga próba otrzymuje nie więcej niż pozostały budżet.

Dopuszczone jest jedno automatyczne ponowienie dla HTTP 408, 429, 500, 502, 503 i 504 oraz wybranych błędów połączenia. `Retry-After` może zawierać liczbę sekund albo datę HTTP. Oczekiwanie przekraczające pozostały budżet lub niefinitywna wartość liczbowa wyłączają ponowienie. Nieznany format jest ignorowany. Domyślna przerwa wynosi 250 ms. Błędy trwałe, niepoprawny JSON, niezgodny identyfikator i anulowanie nie uruchamiają automatycznego ponowienia.

## Pamięć podręczna

Przed przyjęciem danych z sieci lub pamięci sprawdzane są dekodowanie i zgodność identyfikatora. Nieudana odpowiedź nie trafia do własnej pamięci jako artykuł. Poprawna odpowiedź z jawnie pustym tekstem pozostaje poprawnymi danymi; renderer pokazuje jej pusty stan.

Ręczne ponowienie pomija lokalną pamięć URLSession i własną pamięć odpowiedzi `no-store`, wysyłając `Cache-Control: no-cache` oraz `Pragma: no-cache`. Poprawny wynik aktualizuje własny cache, a jeśli nowa odpowiedź nie wymaga tego cache, usuwa poprzedni wpis. Kolejne wejście nie odzyskuje starszego tekstu sprzed ręcznego odświeżenia.

## Stan widoku

Oba rodzaje szczegółów używają `DetailLoaderView`. Tożsamość całego loadera zależy od pochodzenia i identyfikatora wpisu, a tożsamość zadania także od licznika ponowień. Wynik starego albo anulowanego zadania nie zmienia bieżącego ekranu. Opuszczenie ekranu zwalnia stan ładowania; poprawnie pobrana treść pozostaje stabilna.

## Weryfikacja

Przypadki XCTest obejmują błędy HTTP, anulowanie, `Retry-After`, błędny JSON i identyfikator, odświeżenie cache oraz ścieżkę stron czasopisma. Pełny Xcode jest oddzielną bramką wydania.

Lokalna sonda Swift Linux uruchamia rzeczywiste metody produkcyjne z kontrolowanym transportem. Bazowy kod wykonywał dwa żądania przy HTTP 404; poprawiony wykonuje jedno. Niezależny zestaw 18 przypadków transportu i cache przeszedł bez błędów. Nie jest to test sieci na fizycznym iPhonie.
