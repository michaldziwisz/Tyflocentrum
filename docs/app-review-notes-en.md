# App Review Information — angielska wersja notatki

Tekst do wklejenia w pole **App Review Information → Notes** w App Store Connect.
App Review czyta po angielsku, więc to jest wersja, która idzie do Apple.
Polska wersja (`notatki-do-app-review.md`) zostaje jako źródło i do naszego wglądu —
przy każdej kolejnej wysyłce aktualizujemy oba pliki.

Dlaczego to nie jest formalność: **najważniejsza funkcja aplikacji, czyli kontakt
z audycją, jest widoczna tylko wtedy, gdy trwa audycja interaktywna.** Recenzent,
który trafi na aplikację w środku dnia, po prostu jej nie zobaczy i może uznać, że
funkcja nie istnieje albo że aplikacja jest niekompletna.

---

## Treść do wklejenia (angielski)

TyfloCentrum is the official client for Tyflopodcast, Tyfloświat and Tyfloradio —
media services run by the Institute for Regional Development Foundation
(Fundacja Instytut Rozwoju Regionalnego), a Polish non-profit serving blind and
partially sighted people. The app is built for VoiceOver users: accessibility is
its reason to exist, not an add-on.

### No account or sign-in required

All content is public. There is no registration, no in-app purchases, and no
content locked behind any condition. You can review every feature without
credentials.

### Where things are

- **Nowości** (What's new) — a combined list of the latest podcast episodes and articles.
- **Podcasty** (Podcasts) and **Artykuły** (Articles) — the same content grouped by category.
- **Szukaj** (Search) — searches both services.
- **Tyfloradio** — live radio player and the broadcast schedule.

Selecting an episode from any list opens the player. With VoiceOver enabled, Magic
Tap (a two-finger double tap) pauses and resumes playback.

### TIME-DEPENDENT FEATURE: contacting the live show

The contact form — both text and voice messages — appears **only while an
interactive show is on air** on Tyfloradio. The app asks the server about this
(`tyflopodcast.net`, parameter `ac=current`) and shows the contact section when the
server reports that a show is live. Outside broadcast hours this section is hidden,
and **this is intended behaviour, not a bug**.

Live shows are usually held in the evening, Polish time (CET/CEST), most often on
Tuesdays, Wednesdays and Thursdays. The current schedule is visible in the
**Tyfloradio** tab and publicly at `https://tyflopodcast.net`.

If you happen to review the app outside broadcast hours and would like to see this
flow, please contact us at the address given as our Support URL — **we will give you
the exact date and time of the next live show**, so you can see the feature working
with no changes to the app or the server.

**We deliberately do not enable a fake "show is live" mode for review.** The same
server also serves our Android app, our Windows app and the website, and the
"a show is on air" flag reaches all listeners at once. Switching it on artificially
would mislead real users, who would be invited to contact a show that is not
actually broadcasting. We would rather give you a precise time slot than
misrepresent the state of the service.

### Microphone

Microphone access is used solely to record a voice message for the live show.
Recording is **always initiated by the user**, via a button on the contact screen.
The recording is sent to the Tyfloradio editorial team and is not used for anything
else. The app never records in the background or without an explicit user action.
Declining microphone access does not block any other part of the app.

### Push notifications

Push notifications are **disabled** in this version. The supporting code exists, but
the user interface and device registration are inactive in the Release build — we did
not want to ship a feature that only appears to work. No device identifier is
transmitted. Enabling push is planned for a future version, together with an updated
privacy policy and App Privacy answers.

### iPad

The app runs on iPhone and iPad from the same codebase. Features that depend on
iPhone-specific sensors (proximity, the so-called "ear mode" while recording) are
hidden and disabled on iPad, where they make no sense.

### Content and rights

Podcasts, articles and the radio stream come from services run by the Institute for
Regional Development Foundation (Tyflopodcast, Tyfloświat, Tyfloradio). This app is
the official client for those services, developed in agreement with their editorial
team. The same content is publicly available through a web browser.

### Accessibility

This app is built for screen reader users, and that is its primary purpose. All
elements carry VoiceOver labels, Dynamic Type is supported, and lists expose
accessibility actions. If anything cannot be operated with VoiceOver during review,
please report it as a bug — for us that is a critical defect, not a cosmetic one.

### Language

The app interface and all content are in Polish, as the services it serves are Polish.

---

## Notatki tłumaczeniowe (dla nas, nie do wklejania)

Kilka decyzji, żeby przy następnej aktualizacji nie trzeba było ich podejmować od nowa.

- **Nazwy zakładek zostawione po polsku, z angielskim objaśnieniem w nawiasie.**
  Recenzent widzi w aplikacji polskie napisy, więc tłumaczenie samych nazw
  utrudniłoby mu nawigację. Podajemy oryginał i tłumaczenie obok.
- **Nazwa Fundacji podana po angielsku i po polsku.** Apple sprawdza prawa do treści
  i nazwy, a nazwa polska jest tą, którą znajdzie w rejestrach.
- **„Institute for Regional Development Foundation"**, nie tłumaczenie dosłowne
  słowo w słowo — to funkcjonujący angielski odpowiednik nazwy tej organizacji.
- **Dodany akapit o języku aplikacji.** Nie ma go w polskiej wersji, bo tam jest
  oczywisty. Recenzentowi trzeba powiedzieć wprost, że polski interfejs to zamiar,
  a nie brakujące tłumaczenie — inaczej może to zgłosić jako defekt.
- **„this is intended behaviour, not a bug"** zostało wytłuszczone celowo. To jedno
  zdanie chroni przed odrzuceniem z powodu funkcji, której recenzent nie zobaczy.

## Do uzupełnienia przed wysyłką

- [x] Privacy Policy URL: `https://michaldziwisz.github.io/Tyflocentrum/privacy/`
- [x] Support URL: `https://michaldziwisz.github.io/Tyflocentrum/`
- [ ] potwierdzić z redakcją, czy da się włączyć tryb testowy audycji na żądanie;
      jeśli nie, zamiast tego podać konkretną datę i godzinę najbliższej audycji
- [ ] sprawdzić spójność „App Privacy" w App Store Connect z `PrivacyInfo.xcprivacy`
      (rozbieżność między nimi jest częstym powodem odrzucenia)
