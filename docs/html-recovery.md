# Odzyskiwanie treści w SafeHTMLView

## Zasady

`HTMLRenderState` rozróżnia próbę, potwierdzony sukces i błąd. Zdrowy, niezmieniony dokument nie jest przeładowywany przy aktualizacji SwiftUI, co chroni pozycję czytania. Potwierdzeniem sukcesu jest callback `didFinish`, nie samo wywołanie `loadHTMLString`.

`SafeHTMLCoordinatorLogic` wiąże callbacki z konkretną nawigacją WebKita. Stare i nieidentyfikowalne callbacki nie kasują timeoutu ani wyniku nowej próby. Po zakończeniu nawigacji nie mogą zmienić jej wyniku. Zakończenie procesu WebKita jest osobnym zdarzeniem, także dla wcześniej poprawnie wyświetlonej treści.

Błąd renderowania, przerwanie procesu lub timeout uruchamiają najwyżej jedno automatyczne odtworzenie już pobranego HTML. Następna porażka pokazuje przycisk „Wczytaj treść ponownie”. Anulowanie aktywnej próby wymaga ponowienia ręcznego i nie uruchamia pętli. Opuszczenie widoku blokuje dalsze odzyskiwanie.

Pusty tekst ma jawny komunikat, bez pozostawienia widocznego poprzedniego dokumentu. CSP, wyłączenie JavaScriptu i ograniczenia otwierania linków pozostają zachowane.

## Testy

- Czysty rdzeń ma 13 wykonywalnych testów XCTest. Dwa dodatkowe przypadki wykazały, a następnie potwierdziły usunięcie błędnego przyjmowania spóźnionego sukcesu oraz błędu nawigacji po zakończeniu. Wszystkie przeszły na Swift Linux.
- Testy koordynatora w Xcode sprawdzają tożsamość nawigacji, anulowanie, działający timeout, ograniczenie ponowień, zachowanie bazowego URL i zakończenie widoku. Obiekty `WKNavigation` powstają przez rzeczywiste `WKWebView.loadHTMLString`, bez niebezpiecznego rzutowania.
- Dwa testy UI uruchamiają kontrolowaną pojedynczą lub podwójną awarię, a następnie sprawdzają konkretny akapit w prawdziwym drzewie `WKWebView`. Nie korzystają z zastępczej etykiety tekstowej. Do wyniku dołączane są zrzuty ekranu.
- Iniekcja awarii istnieje tylko w konfiguracji DEBUG z argumentem `UI_TESTING`. Build TestFlight jej nie zawiera.

Sonda starego `updateUIView` na atrapie WebKita dowodziła blokady ponowienia identycznego HTML, a nie fizycznej awarii na iPhonie. Testy Linux nie zastępują testów UIKit/WebKit w Xcode ani odsłuchu VoiceOver na urządzeniu.
