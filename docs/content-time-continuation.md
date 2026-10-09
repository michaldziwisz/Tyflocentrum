# Kontynuacja pomiarów odświeżania

Testy ręcznego gestu rozdzielono na niezależne powierzchnie: Nowości, wszystkie podcasty, kategoria podcastów, wszystkie artykuły, kategoria artykułów, wyszukiwanie. Każdy przechodzi zmiany metadanych w jednym procesie bez zmian ID. Diagnostyka DEBUG mierzy granicę await i publikacji modelu; nie zmienia warunków anulowania. Oba workflow zachowują surowy xcresult i diagnostykę niezależnie od powodzenia. Wynik diagnostycznego workflow ma kod0 także przy porażkach, więc rozstrzygają tests.json i summary.json, nie zielona ikona przebiegu.
