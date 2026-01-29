# Tyflocentrum — App Store readiness (postęp prac)

Data: **2026-01-29**

Ten plik jest „żywą” check‑listą wdrożeń pod wydanie **1.0** (App Store) na podstawie `CODE_REVIEW_APPSTORE.md`.

## Stan CI

- Baseline (przed poprawkami z tej iteracji): workflow `iOS (unsigned IPA)` – **success** (run `21481970583`).
- Po poprawkach z tej iteracji: workflow `iOS (unsigned IPA)` – **success** (run `21484408407`).

## Wdrożone (bez Apple Developer Program)

- Usunięto martwy, legacy kod renderowania HTML (`HTMLTextView`, `HTMLRendererHelper`).
- Push (na teraz): UI i automatyczna rejestracja powiadomień są ukryte/wyłączone w buildzie Release (żeby nie dostarczać „pozornej” funkcji).
- Zoptymalizowano `Podcast.PodcastTitle.plainText` (memoizacja + szybka ścieżka bez parsowania HTML) i dodano testy regresji.

## Wymaga Apple Developer Program / zewnętrznej konfiguracji

- Realne powiadomienia push przez APNs:
  - capability **Push Notifications** + entitlements dla docelowego bundle ID,
  - klucz APNs (`.p8`) + `teamId` + `keyId`,
  - faktyczna wysyłka do APNs w `push-service` (obecnie MVP tylko loguje fan‑out).

## Do zrobienia poza kodem (App Store Connect)

- Dodać **Privacy Policy URL** oraz **Support URL**.
- Uzupełnić „App Privacy” zgodnie z realnym działaniem aplikacji (kontakt, głosówki, ulubione/ustawienia; push jeśli zostanie włączony).
- Przygotować notatki do App Review (co i gdzie przetestować).

## Kandydaci na kolejne iteracje (nie blokują 1.0)

- Ujednolicenie formatowania (SwiftFormat/SwiftLint) w wybranych plikach wskazanych w review.
- Migracja `NavigationView` → `NavigationStack`.
- Rozważenie cache (URLCache / in‑memory) dla list, jeśli pojawią się problemy z energią/szybkością.
