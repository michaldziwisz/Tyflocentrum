# Kontynuacja pomiarów odświeżania

## Kandydat TestFlight 1.0.3 (5)

Poprawkę odświeżania scalono po niezależnym odbiorze przebiegu 38003773964: 259 testów zaliczonych, bez porażek i pominięć. Numer kompilacji podniesiono do 5 w konfiguracjach Debug i Release. Kod aplikacji i testów pozostaje identyczny z odebranym kandydatem. Wysyłka dotyczy wyłącznie TestFlight, bez zgłoszenia do recenzji App Store. Fokus i mowa VoiceOver na fizycznym iPhonie pozostają do sprawdzenia.

Testy ręcznego gestu rozdzielono na niezależne powierzchnie: Nowości, wszystkie podcasty, kategoria podcastów, wszystkie artykuły, kategoria artykułów, wyszukiwanie. Każdy przechodzi zmiany metadanych w jednym procesie bez zmian ID. Diagnostyka DEBUG mierzy granicę await i publikacji modelu; nie zmienia warunków anulowania. Oba workflow zachowują surowy xcresult i diagnostykę niezależnie od powodzenia. Wynik diagnostycznego workflow ma kod0 także przy porażkach, więc rozstrzygają tests.json i summary.json, nie zielona ikona przebiegu.

Pełny workflow po suicie i archiwum wykonuje kontrolny RED na eb1561fa008abb9427b1de332acd841da37e0c56. `tools/native_refresh_red.py` kopiuje z kandydata tylko trzy pliki aparatury (testy UI, dane DEBUG, inicjalizacja testowa App). Modele, cache i widoki list pozostają z bazy. Wymaga pojedynczej porażki oczekiwania czasu po potwierdzonych dwóch początkowych wierszach, a nie błędu launch. Surowy wynik RED przechowuje osobno od pełnego wyniku kandydata.
