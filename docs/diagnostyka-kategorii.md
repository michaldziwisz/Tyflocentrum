# Jednorazowy pomiar ładowania kategorii

Ta gałąź nie jest kandydatem do wydania i nie może być scalona do aplikacji.
Baza: `5299e62cd78b7aff2179856209a501c308525ece`.

Cel: odróżnić anulowanie zadania widoku, błąd odpowiedzi atrapy, błąd dekodowania i utratę stanu listy. Komunikat z przyciskiem ponowienia może oznaczać zarówno błąd, jak i stan `hasLoaded=false` po anulowaniu; sam zrzut tego nie rozstrzyga.

Uruchamiany jest wyłącznie `testPullToRefreshUpdatesLists`, raz, na iPhone 17 Pro / iOS 26.5. Test zachowuje całą sekwencję, timeouty i asercje. Jedyna zmiana w jego pomocniku to flaga zapisu śladu. Nie wykonujemy automatycznego klikania ponowienia ani ponownego testu.

`CategoryLoadTrace` wymaga DEBUG, UI_TESTING i UI_TESTING_CATEGORY_TRACE. Zapisuje granice wywołań widoku, modelu, API i atrapy; błędy zawierają typ, domain, code i stan anulowania. JSONL w dokumentach aplikacji oraz log systemowy stanowią dwa kanały odbioru. Wartości w atrapie pozostają niezmienione. Logger jest synchroniczny i może zmieniać czas wykonania: brak odtworzenia nie dowodzi naprawy ani historycznej przyczyny. Izolacja jednego testu nie zachowuje obciążenia pełnego zestawu.

Workflow nie archiwizuje Release, nie podpisuje i niczego nie wysyła do Apple. Zapisuje wynik testu również przy porażce. Jedno zielone wykonanie nie zastępuje czerwonej bramki wydania.
