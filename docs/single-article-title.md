# Pojedynczy tytuł artykułu

Pełny tytuł artykułu jest jednym nagłówkiem w treści, a data osobnym elementem bez cechy Header. Pasek nawigacji nie powtarza tytułu, ale zachowuje Wstecz i ulubione. Treść WKWebView i jej śródtytuły pozostają bez zmian.

## Zakres poprawki

`ArticleHeaderView` jest wspólny dla gotowego detalu oraz stanów ładowania i błędu `DetailLoaderView`. Identyfikator `articleDetail.header` nadal wskazuje nagłówek, a nowy `articleDetail.date` odrębną datę. Pusty tytuł nawigacji jest ustawiony w detalu i loaderze. Numer czasopisma bez spisu treści też wyłącza tytuł paska, gdy pokazuje treść przez `DetailedArticleView`. Widok numeru ze spisem zachowuje swój tytuł nawigacji.

Bez zmian w logice pobierania, ponawiania, metadanych czasów, cache, odtwarzacza, push i komentarzy. Bez usuwania śródtytułów z HTML. Próbka pięciu najnowszych wpisów i czterech stron publicznego REST Tyfloświata zawierała 428 nagłówków h1..h6, żaden nie był pełnym tytułem danego dokumentu, także po normalizacji odstępów. Nie ustalono dokładnego artykułu ze zgłoszenia.

## Testy i odtworzenie

Testy `TyflocentrumUITests/TyflocentrumSmokeTests/testSingleArticleTitle*` uruchamiają rzeczywistą aplikację przez listy Nowości, wszystkich artykułów, kategorii, wyszukiwania, ulubionych wpisów i stron, czasopisma i numeru bez spisu treści. Osobno badają błąd, ręczne ponowienie, ładowanie i Wstecz. Wymagają nagłówka raz, pełnego tytułu, oddzielnej daty, zachowanych h2/h3 i akapitów WKWebView oraz działania ulubionych, arkusza udostępniania i powrotu do właściwej listy. Długi tytuł zawiera polskie znaki i encję HTML.

Dane `UI_TESTING_ARTICLE_TITLE` są syntetyczne i dostępne tylko w DEBUG. Odczyt AX zbiera istniejące obiekty UIAccessibility. Nie tworzy zastępczej treści. SwiftUI `AccessibilityNode` nie przekazuje identyfikatora przez protokół UIKit, dlatego cechy są wiązane z pełną unikalną etykietą; stabilne ID sprawdza niezależnie XCUI. Poziomy śródtytułów są sprawdzane na elementach AX WebKita, z wartościami 2 i 3.

Rzeczywisty pomiar RED jest na commicie `0a9889bf93fea4b8f6156b078b32d3cf5c5b8d24`, z produkcyjnymi widokami bazy `47006418219548a563188bbdde4a64d9d8497950`: workflow `iOS (unsigned IPA)`, run `38016968099`. Siedem nowych testów wykazało `body=1;navigation=1;html=0`, a 259 wcześniejszych testów przeszło. Ósmy test diagnostyczny zakładał błędnie, że pojedynczy timeout pokaże błąd zamiast odzyskania; obecnie używa jednorazowego HTTP 404 i rzeczywistego przycisku ponowienia. Początkowy D1 `38016678462` nie był RED produktu, ponieważ zatrzymał się na kompilacji aparatury.

Pełną bramkę uruchamia `bash scripts/build-unsigned-ipa.sh` na macOS z Xcode. Lokalny Swift/Linux i lint nie zastępują tego przebiegu. Workflow zachowuje dokładny SHA, `.xcresult`, summary/tests JSON, drzewa AX oraz screenshoty. Test pojedynczej drogi na symulatorze można wybrać argumentem `-only-testing:TyflocentrumUITests/TyflocentrumSmokeTests/testSingleArticleTitleNews` przy zwykłym `xcodebuild test`.

Aparatura ładowania `UI_TESTING_HOLD_TITLE_DETAIL` zawiesza zadanie prawdziwego
`DetailLoaderView` przez asynchroniczną kontynuację, przed wywołaniem API.
Jest to hook wyłącznie `#if DEBUG` i trzech jawnych flag UI_TESTING, bez zmiany
kodu Release, timeoutów, cache ani API. Wstecz anuluje zadanie, usuwa kontynuację
i pozwala przy następnym wejściu pobrać treść. Test odczytuje stan oczekiwania
i licznik anulowań oraz rzeczywisty ProgressIndicator. Przycisk DEBUG pozwala
też jawnie zwolnić odpowiedź. Dawny stall URLProtocol nie był deterministyczny,
ponieważ API po 12 s ponawiało próbę i dostawało już treść.

Długie etykiety są wyszukiwane predykatem po pełnym label, bez limitu skróconego
selektora XCUI. Systemowy arkusz jest wykrywany jako ActivityListView i zamykany
przez jego rzeczywisty PopoverDismissRegion (punkt poza aktualną ramką popovera)
lub gest na nagłówku arkusza. Test wymaga zniknięcia arkusza przed Wstecz.
To obsługa dotykowa XCUI, nie test gestu VoiceOver.

Granica pomiaru: SwiftUI/XCUI i obiekty UIAccessibility na symulatorze, nie odsłuch fizycznego VoiceOver. Poprawka nie zmienia wersji i nie publikuje aplikacji.
