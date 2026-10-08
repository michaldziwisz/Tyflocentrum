# Czasy treści na listach

Obok daty publikacji iOS pokazuje „Czytanie: około 6 min” albo długość audycji, np. „Czas trwania: 1 godz. 23 min 4 s”. Gdy nie ma wiarygodnego pomiaru, pojawia się „Czas niedostępny”. Dotyczy to Nowości, wszystkich wpisów, kategorii, wyszukiwarki, ulubionych i artykułów w numerach Tyfloświata. Okładki numerów i pliki PDF nie otrzymują czasu czytania całego wydania.

Nazwa istniejącego wiersza dostępności zawiera czas raz, pełnymi polskimi jednostkami. Sam czas nie jest osobnym elementem fokusu. Zachowane są identyfikatory wierszy, ich akcje i układ ScrollView z LazyVStack na ekranie Nowości.

## Dane i odporność

* Podcasty otrzymują opcjonalne `tyflocentrum` w istniejącym żądaniu WordPressa. `duration_seconds` jest liczbą zmiennoprzecinkową, zaokrąglaną w górę do sekundy dopiero po walidacji. Wspierane są tylko schema 1 i audio_status ready, wartości dodatnie, skończone i nie większe niż 2147483647 sekund.
* Czytanie korzysta z `https://tyflocentrum.tyflo.eu.org/v1/metadata`. Osobne klucze posts/pages o tym samym ID nie mieszają się. Partie zawierają najwyżej 50 unikalnych poprawnych ID; odpowiedź jest składana po kluczach, nie kolejności. Obce ID są ignorowane, powtórzone ID w odpowiedzi stają się nieznane.
* Dodatkowe pobranie metadanych Tyfloświata i ulubionych jest zadaniem listy uruchamianym niezależnie od jej zawartości. Nigdy nie opóźnia zwrócenia pierwszej strony, otwarcia artykułu lub wejścia do odtwarzacza. Każda dodatkowa paczka ma limit 3 sekund obejmujący także oczekiwanie transportu. Nie ma automatycznych ponowień.
* Obsługiwane są tylko świeże wyniki schema 1, text_status ready oraz dodatnie całkowite liczniki zgodne z ceil(word_count / 200). Brak modified_gmt w context=embed nie odrzuca wyniku; znana nowsza modyfikacja źródła odrzuca stary czas.
* Współdzielony cache dodatkowego klienta metadanych ma najwyżej 512 wpisów, wynik gotowy jest przechowywany przez najwyżej 5 minut, a nieznany lub błąd przez 30 sekund. Czas czytania dodatkowo wygasa po 24 godzinach od checked_at. Jest sprawdzany również na otwartym ekranie i po powrocie z tła, nie tylko przy pobraniu. Limit pamięci współdzielonej nie ogranicza liczby pozycji aktualnej listy: także po doładowaniu ponad 512 wpisów wszystkie zachowują możliwość otrzymania czasu. Stan pojedynczego ekranu obejmuje jego aktualne wpisy i usuwa rekordy pozycji, które zniknęły z tej listy.
* Długości podcastów pobrane razem z listą WordPressa korzystają z istniejącego cache tej listy, a nie z osobnego limitu 3 sekund ani cache 5 minut. Starsze ulubione uzupełnia dodatkowy klient. Limit 24 godzin od checked_at dotyczy wyłącznie wyników czytania z cache Tyfloświata; WordPress nie dostarcza tego pola dla audio.
* Równoczesne żądania wspólnych kluczy korzystają z tych samych aktywnych partii. Anulowanie ostatniego odbiorcy anuluje transport. Odświeżenie usuwa stare wyniki; spóźniony callback nie przywraca poprzedniego cache ani stanu listy.
* Wadliwe opcjonalne pola nie psują dekodowania wpisu ani całej listy. Stare ulubione i cache numerów pozostają czytelne, z tymi samymi kluczami i kolejnością. Ulubione pobierają same metadane partiami, także dla dawniej zapisanych podcastów, bez pełnego tekstu czy nagrania.

## Weryfikacja

`ContentTimeContractTests` wykonuje wspólne 50 syntetycznych przypadków kontraktowych. `ContentTimeTests`, `ContentTimeClientTests` i `ContentTimeIntegrationTests` sprawdzają dekodowanie, odmianę, daty, TTL, rozłączne typy, partie, duplikaty, awarie, anulowanie, stare ulubione oraz niezależność listy od zablokowanego transportu metadanych. Rejestr URL w testach sprawdza brak żądania pełnej treści i audio przy ładowaniu listy. Test `testLongListModifierDeliversEveryTimeWithBoundedCache` montuje rzeczywisty modyfikator SwiftUI w UIHostingController i wymaga wszystkich 600 wartości, zachowując limit 512 wpisów cache oraz paczki po 50 ID.

`tools/test_content_time_list.py --out <katalog-dowodow> --zapisz` kompiluje niezmieniony kod wyboru żądań i stanu listy z lekkim adapterem. Sprawdza pełne 600 żądań, ich kolejność, utrzymanie czasów przy zablokowanej kolejnej stronie oraz współdzielony cache na pustym zimnym ekranie. Bez `--zapisz` pokazuje wyłącznie plan. Ten test logiki działa również na Linuxie; nie udaje renderowania SwiftUI i nie zastępuje testu Xcode. Istniejący skrypt pełnego CI uruchamia oba poziomy.

Testy UI `testContentTimesAcrossAllLists` i `testMetadataOutageKeepsRealArticleAndPlaybackReachable` odczytują etykiety wierszy i akapit z prawdziwego WKWebView na symulatorze. Dołączają etykiety tekstowe i zrzuty. Atrapa metadanych jest ograniczona do DEBUG oraz jawnych argumentów testów; Release nie aktywuje trybu UI_TESTING.

Pełne sprawdzenie wykonuje istniejący workflow `ios-unsigned-ipa.yml`: lint SwiftFormat 0.58.7, XCTest i XCUITest oraz archiwum Release na macos-26. Testy symulatora nie są pomiarem mowy VoiceOver na fizycznym iPhonie. Wydanie do TestFlight pozostaje osobnym podpisanym przebiegiem po odbiorze kodu.
