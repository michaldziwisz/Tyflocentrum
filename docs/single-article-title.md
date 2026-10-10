# Pojedynczy tytuł artykułu

Kontrakt: pełny tytuł artykułu w treści jako jeden nagłówek, data osobno. Pasek nawigacji nie powtarza tytułu, ale zachowuje Wstecz i ulubione. Treść WKWebView i jej śródtytuły pozostają bez zmian.

Testy `testSingleArticleTitle*` uruchamiają rzeczywistą aplikację przez listy Nowości, wszystkich artykułów, kategorii, wyszukiwania, ulubionych, czasopisma i jego wariantu bez spisu treści. Dane `UI_TESTING_ARTICLE_TITLE` są syntetyczne, dostępne tylko w DEBUG. Odczyt AX zbiera istniejące obiekty UIAccessibility; nie tworzy zastępczej treści. Nie jest to odsłuch fizycznego VoiceOver.

Pierwszy commit testowy zachowuje wszystkie produkcyjne widoki bazy `47006418219548a563188bbdde4a64d9d8497950` i jest przeznaczony do pomiaru RED. Oczekiwane powtórzenie liczone jest oddzielnie w elemencie treści oraz w tekście paska nawigacji, bez sumowania etykiet przodków.
