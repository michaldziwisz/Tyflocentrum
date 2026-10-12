# Czytanie komentarzy na iOS

Ekran Komentarze pokazuje od razu pełne treści, autora, datę (jeżeli serwer ją podaje) i kontekst odpowiedzi. Nie trzeba otwierać każdego wiersza ani używać Rozwiń. Długi komentarz przewija się razem z resztą dyskusji. Odświeżanie jest dostępne przyciskiem „Odśwież komentarze” na pasku; błąd ma osobny przycisk ponowienia.

## Układ i dostępność

Jedna powierzchnia SafeHTMLView zawiera semantyczną listę HTML. Każdy komentarz ma osobny element listy oraz nagłówek autora. Akapity i odnośniki pozostają osobnymi elementami dostępności. Nie zastępujemy dokumentu pojedynczą etykietą VoiceOver. Unikamy kilkudziesięciu zagnieżdżonych webview i stałej wysokości ucinającej długi tekst.

SafeHTMLView nie został przebudowany. Zachowuje wyłączenie JavaScript, CSP, filtrowanie schematów, otwieranie bezpiecznych linków poza treścią oraz istniejące odzyskiwanie po błędzie renderowania. Metadane autora i odpowiedzi są kodowane jako tekst HTML. Treść komentarza pozostaje w oryginalnym HTML z API.

Usunięto prywatne PodcastCommentRowView i PodcastCommentDetailView, których jedyną rolą było dodatkowe przejście do odczytu. Nie było innych konsumentów. Szczegół podcastu nadal otwiera wspólny ekran Komentarze; osadzanie całej dyskusji pod odtwarzaczem jest osobnym zakresem.

## Granice

Pozostaje dotychczasowe pobieranie do 100 komentarzy. Ta zmiana prezentacji nie dodaje paginacji ani publikowania odpowiedzi. Dla rodzica spoza pobranej porcji kontekst zawiera numer komentarza, bez wymyślania jego autora. Brak lub błędna data nie blokuje treści i nie daje zmyślonej daty. Wartość WordPress `date` jest lokalnym czasem serwisu, zachowywanym bez przesunięcia do strefy telefonu.

## Weryfikacja

Natywny test `testCommentsShowFullBodiesWithoutOpeningRows` na niezmienionym kodzie produktu 938231e7 oblewa dokładnie brak treści na liście (run 38174849518, testowy commit 9ba19d7). Testy kandydata obejmują pełny tekst, długi koniec komentarza, akapity, linki, blokadę skryptu i niebezpiecznego schematu, daty, rodzica spoza porcji, pusty wynik, błąd/ponowienie, ładowanie/timeout i większy tekst. Test starej drogi wejścia zachowuje kontrolę licznika oraz odczytu komentarza, ale nie wykonuje już usuniętej akcji otwarcia pojedynczego wiersza.

Automatyczny pomiar drzewa WebKita i symulatora nie zastępuje fizycznego VoiceOver. Próba czytnika i wydanie do TestFlight wymagają osobnego etapu. Numer wersji i buildu pozostaje bez zmian.
