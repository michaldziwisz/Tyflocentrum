# Czasy treści na listach

Obok daty publikacji iOS pokazuje „Czytanie: około 6 min” albo długość audycji, np. „Czas trwania: 1 godz. 23 min 4 s”. Gdy nie ma wiarygodnego pomiaru, pojawia się „Czas niedostępny”. Dotyczy to Nowości, wszystkich wpisów, kategorii, wyszukiwarki, ulubionych i artykułów w numerach Tyfloświata. Okładki numerów i pliki PDF nie otrzymują czasu czytania całego wydania.

Nazwa istniejącego wiersza dostępności zawiera czas raz, pełnymi polskimi jednostkami. Sam czas nie jest osobnym elementem fokusu. Zachowane są identyfikatory wierszy, ich akcje i układ ScrollView z LazyVStack na ekranie Nowości.

## Dane i odporność

* Podcasty otrzymują opcjonalne `tyflocentrum` w istniejącym żądaniu WordPressa. `duration_seconds` jest liczbą zmiennoprzecinkową, zaokrąglaną w górę do sekundy dopiero po walidacji. Wspierane są tylko schema 1 i audio_status ready, wartości dodatnie, skończone i nie większe niż 2147483647 sekund.
* Czytanie korzysta z `https://tyflocentrum.tyflo.eu.org/v1/metadata`. Osobne klucze posts/pages o tym samym ID nie mieszają się. Partie zawierają najwyżej 50 unikalnych poprawnych ID; odpowiedź jest składana po kluczach, nie kolejności. Obce ID są ignorowane, powtórzone ID w odpowiedzi stają się nieznane.
* Pobranie metadanych jest zadaniem listy uruchamianym niezależnie od jej zawartości. Nigdy nie opóźnia zwrócenia pierwszej strony, otwarcia artykułu lub wejścia do odtwarzacza. Krótki limit 3 sekund obejmuje całą operację, także oczekiwanie transportu. Nie ma automatycznych ponowień.
* Obsługiwane są tylko świeże wyniki schema 1, text_status ready oraz dodatnie całkowite liczniki zgodne z ceil(word_count / 200). Brak modified_gmt w context=embed nie odrzuca wyniku; znana nowsza modyfikacja źródła odrzuca stary czas.
* Cache metadanych ma najwyżej 512 wpisów, wynik gotowy jest przechowywany przez najwyżej 5 minut, a nieznany lub błąd przez 30 sekund. Czas czytania dodatkowo wygasa po 24 godzinach od checked_at. Jest sprawdzany również na otwartym ekranie i po powrocie z tła, nie tylko przy pobraniu.
* Równoczesne żądania wspólnych kluczy korzystają z tych samych aktywnych partii. Anulowanie ostatniego odbiorcy anuluje transport. Odświeżenie usuwa stare wyniki; spóźniony callback nie przywraca poprzedniego cache ani stanu listy.
* Wadliwe opcjonalne pola nie psują dekodowania wpisu ani całej listy. Stare ulubione i cache numerów pozostają czytelne, z tymi samymi kluczami i kolejnością. Ulubione pobierają same metadane partiami, także dla dawniej zapisanych podcastów, bez pełnego tekstu czy nagrania.

## Weryfikacja

`ContentTimeContractTests` wykonuje wspólne 50 syntetycznych przypadków kontraktowych. `ContentTimeTests`, `ContentTimeClientTests` i `ContentTimeIntegrationTests` sprawdzają dekodowanie, odmianę, daty, TTL, rozłączne typy, partie, duplikaty, awarie, anulowanie, stare ulubione oraz niezależność listy od zablokowanego transportu metadanych. Rejestr URL w testach sprawdza brak żądania pełnej treści i audio przy ładowaniu listy.

Testy UI `testContentTimesAcrossAllLists` i `testMetadataOutageKeepsRealArticleAndPlaybackReachable` odczytują etykiety wierszy i akapit z prawdziwego WKWebView na symulatorze. Dołączają etykiety tekstowe i zrzuty. Atrapa metadanych jest ograniczona do DEBUG oraz jawnych argumentów testów; Release nie aktywuje trybu UI_TESTING.

Pełne sprawdzenie wykonuje istniejący workflow `ios-unsigned-ipa.yml`: lint SwiftFormat 0.58.7, XCTest i XCUITest oraz archiwum Release na macos-26. Testy symulatora nie są pomiarem mowy VoiceOver na fizycznym iPhonie. Wydanie do TestFlight pozostaje osobnym podpisanym przebiegiem po odbiorze kodu.
