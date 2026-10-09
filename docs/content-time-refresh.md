# Odświeżanie czasu bez restartu

Regresje `testTimeRefreshOldFavoritesSameProcess` i `testTimeRefreshInlineAndReadingSameProcess` używają jednego uruchomienia aplikacji na scenariusz. Przycisk testowy zmienia wyłącznie odpowiedź atrapy, nie cache, nie ID ani ekran. Po tej zmianie test wykonuje pojedynczy gest odświeżenia i sprawdza rzeczywistą nazwę AX. Kontrolka jest dostępna wyłącznie w DEBUG z argumentem UI_TESTING_TIME_REFRESH.

Pierwszy commit dodaje scenariusz RED do niezmienionej logiki produkcyjnej. Pomiar Swift/Linux nie zastępuje Xcode/SwiftUI ani fizycznego VoiceOver.
