#!/usr/bin/env python3
"""Wpisuje metadane wydania TyfloCentrum do App Store Connect przez API.

PO CO. Strona wersji w App Store Connect to kilkanascie pol w formularzach, ktore
Michal (niewidomy) musialby przejsc czytnikiem, a czesc elementow Apple jest gluchа
na klawiature (zmierzone: filtr wyboru App ID, przycisk Review Agreement). Kazde
pole, ktore da sie wpisac przez API, to jedno pole mniej do wyklikania.

CZEGO TU NIE MA, bo API tego nie obsluguje (specyfikacja 4.4.1, 966 sciezek):
  - utworzenie rekordu aplikacji (/v1/apps ma tylko GET),
  - sekcja App Privacy (zero endpointow deklaracji zbierania danych).
Te dwie rzeczy robi czlowiek. Wszystko inne jest tutaj.

IDEMPOTENTNIE: kazde pole jest USTAWIANE na wartosc docelowa, nie dopisywane.
Powtorne uruchomienie daje ten sam stan. Kategoria wiekowa i kategorie sklepu
sa PATCH-owane, wiec tez sie nie dubluja.

Uzycie:
    python3 tools/metadane_wydania.py --pokaz     # co jest teraz w ASC
    python3 tools/metadane_wydania.py --zapisz    # wpisuje metadane
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import BUNDLE_ID, Asc, BladASC  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE = "pl"

ADRES_POLITYKI = "https://michaldziwisz.github.io/Tyflocentrum/privacy/"
ADRES_WSPARCIA = "https://michaldziwisz.github.io/Tyflocentrum/"

# --- teksty karty sklepu -----------------------------------------------------
# Zrodlo: docs/asc-sciaga-wysylka.md, sekcja "Teksty do wklejenia". Trzymamy je
# TUTAJ, a nie parsujemy z markdownu, bo parser cudzego dokumentu to dodatkowy
# punkt awarii przy czyms, co wysyla sie do Apple raz.

OPIS = """TyfloCentrum daje dostęp do audycji Tyflopodcastu, artykułów Tyfloświata i radia
Tyfloradio — w jednym miejscu, bez zakładania konta.

Aplikacja jest tworzona z myślą o osobach niewidomych i słabowidzących. Obsługa
VoiceOverem nie jest dodatkiem, a punktem wyjścia: wszystkie elementy mają
etykiety, listy udostępniają akcje dostępności, a rozmiar tekstu podąża za
ustawieniami systemu.

Co możesz robić:
• słuchać najnowszych audycji i przeglądać je według kategorii,
• czytać artykuły Tyfloświata, w tym numery czasopisma,
• słuchać Tyfloradia na żywo i sprawdzać ramówkę,
• wyszukiwać w obu serwisach naraz,
• zapisywać ulubione audycje i artykuły,
• wracać do przerwanego odcinka od miejsca zatrzymania,
• zmieniać prędkość odtwarzania i korzystać ze znaczników czasu,
• wysyłać wiadomość tekstową lub głosową do audycji na żywo.

Odtwarzaniem sterujesz też Magic Tapem, czyli dwukrotnym stuknięciem dwoma
palcami przy włączonym VoiceOverze.

Aplikacja nie zawiera reklam, nie zbiera danych do celów marketingowych i nie
wymaga logowania. Treści pochodzą z serwisów Fundacji Instytut Rozwoju
Regionalnego."""

# Bez spacji po przecinkach - spacje zjadaja limit 100 znakow.
SLOWA_KLUCZOWE = ("tyflopodcast,tyfloradio,tyfloświat,niewidomi,VoiceOver,"
                  "dostępność,podcast,radio")

CO_NOWEGO = "Pierwsze wydanie TyfloCentrum dla iPhone'a i iPada."

PRAWA_AUTORSKIE = "2026 Michał Dziwisz"

# --- kontakt do App Review ---------------------------------------------------
# NUMER PODANY PRZEZ MICHALA, zgodny z kontaktem Sterigo w tym samym koncie
# (maska ASC: +486****8803). NIE WYMYSLAJ tu nic: pierwsza wersja tego pliku miala
# numer wzięty z powietrza, ktory trafil do App Store Connect. Pole kontaktowe idzie
# do Apple i do recenzenta - zmyslona dana jest tu gorsza od pustej.
KONTAKT = {
    "contactFirstName": "Michał",
    "contactLastName": "Dziwisz",
    "contactEmail": "michal@dziwisz.net",
    "contactPhone": "+48695918803",
    "demoAccountRequired": False,
}

# --- kategoria wiekowa -------------------------------------------------------
# Wszystko NONE/false. Aplikacja daje dostep do audycji i artykulow redakcyjnych,
# nie ma przemocy, hazardu, tresci dla doroslych ani nieograniczonej przegladarki.
# Wynik powinien wyjsc 4+.
#
# UWAGA na 'unrestrictedWebAccess': aplikacja renderuje HTML artykulow we WLASNYM
# widoku (SafeHTMLView, bez JS, z whitelista schematow), a linki otwiera POZA
# aplikacja, w Safari. To NIE jest nieograniczona przegladarka wbudowana w apke,
# wiec deklarujemy false. Deklaracja 'na zapas' podniosla by kategorie wiekowa
# do 17+ bez powodu.
KATEGORIA_WIEKOWA = {
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "horrorOrFearThemes": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "gambling": False,
    "unrestrictedWebAccess": False,
    "lootBox": False,
    "advertising": False,
    "healthOrWellnessTopics": False,
    "messagingAndChat": False,
    "parentalControls": False,
    "userGeneratedContent": False,
    "kidsAgeBand": None,
    # ageAssurance: czy aplikacja MA WLASNY mechanizm weryfikacji wieku uzytkownika.
    # Nie ma - nie ma kont, logowania ani bramki wiekowej. Apple wymaga tego pola
    # jawnie (HTTP 409 ENTITY_ERROR.ATTRIBUTE.REQUIRED, gdy go brak).
    "ageAssurance": False,
    # Nie jest serwisem spolecznosciowym: nie ma profili, obserwowania ani publikowania
    # tresci przez uzytkownikow. Wiadomosc do audycji idzie do redakcji, nie na forum.
    "socialMedia": False,
}

# --- kategorie sklepu --------------------------------------------------------
# News jako glowna: aplikacja daje dostep do audycji i artykulow redakcyjnych.
KATEGORIA_GLOWNA = "NEWS"
KATEGORIA_DRUGA = "EDUCATION"


def notatka_do_recenzji() -> str:
    """Angielska notatka dla App Review, wyciagnieta z docs/app-review-notes-en.md.

    Bierzemy sekcje miedzy 'Treść do wklejenia (angielski)' a nastepnym separatorem,
    bo dalej w pliku sa nasze notatki tlumaczeniowe, ktorych Apple widziec nie ma.
    Naglowki markdown zamieniamy na czysty tekst - pole notes to zwykly tekst,
    a '###' w tresci wygladalyby jak smiec.
    """
    sciezka = os.path.join(REPO, "docs/app-review-notes-en.md")
    with open(sciezka, encoding="utf-8") as f:
        tekst = f.read()

    znacznik = "## Treść do wklejenia (angielski)"
    if znacznik not in tekst:
        raise SystemExit(f"nie znajduje sekcji '{znacznik}' w {sciezka}")
    po = tekst.split(znacznik, 1)[1]
    # sekcja konczy sie linia '---' na poczatku wiersza
    czesci = po.split("\n---\n", 1)
    tresc = czesci[0].strip()

    linie = []
    for w in tresc.split("\n"):
        w = w.strip()
        if w.startswith("### "):
            linie.append("")
            linie.append(w[4:].upper())
        elif w.startswith("## "):
            linie.append("")
            linie.append(w[3:].upper())
        else:
            # pogrubienia i kursywa markdownu do czystego tekstu
            linie.append(w.replace("**", "").replace("`", ""))
    wynik = "\n".join(linie).strip()
    while "\n\n\n" in wynik:
        wynik = wynik.replace("\n\n\n", "\n\n")
    return wynik


def sprawdz_limity(notatka: str) -> list[str]:
    """Limity Apple. Przekroczenie = odrzucony PATCH w polowie wpisywania metadanych."""
    problemy = []
    limity = [
        ("description", OPIS, 4000),
        ("keywords", SLOWA_KLUCZOWE, 100),
        ("whatsNew", CO_NOWEGO, 4000),
        ("promotionalText", "", 170),
        ("notes (App Review)", notatka, 4000),
    ]
    for nazwa, wartosc, limit in limity:
        if len(wartosc) > limit:
            problemy.append(f"{nazwa}: {len(wartosc)} znakow, limit {limit}")
    return problemy


def pojedynczy(asc: Asc, sciezka: str) -> dict | None:
    """Zwraca zasob 1:1 albo None, gdy go NIE MA.

    PULAPKA, ktora tu wpadla: brak takiego zasobu Apple zglasza DWOMA sposobami -
    czasem HTTP 404, a czasem HTTP 200 z ciałem {"data": null}. Samo `except BladASC`
    lapie tylko pierwszy przypadek, a drugi przechodzi dalej i wywala sie pozniej na
    indeksowaniu None. Skutek bylby najgorszy z mozliwych: awaria w POLOWIE
    wpisywania metadanych, czyli czesc pol zapisana, czesc nie.
    """
    try:
        return asc.get(sciezka).get("data")
    except BladASC as e:
        if e.status == 404:
            return None
        raise


def wersja_i_lokalizacja(asc: Asc, aid: str) -> tuple[str, str]:
    d = asc.get(f"/v1/apps/{aid}/appStoreVersions", **{"limit": 10})
    if not d.get("data"):
        raise SystemExit("aplikacja nie ma zadnej wersji - utworz wersje 1.0 w App Store Connect")
    wersja = d["data"][0]
    vid = wersja["id"]
    print(f"  wersja {wersja['attributes'].get('versionString')} "
          f"({wersja['attributes'].get('appStoreState')}) id={vid}")

    lok = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", **{"limit": 20})
    for x in lok.get("data", []):
        if x["attributes"]["locale"] == LOCALE:
            return vid, x["id"]
    raise SystemExit(f"wersja nie ma lokalizacji '{LOCALE}' - sprawdz Primary Language aplikacji")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    grupa = ap.add_mutually_exclusive_group(required=True)
    grupa.add_argument("--pokaz", action="store_true")
    grupa.add_argument("--zapisz", action="store_true")
    a = ap.parse_args()

    notatka = notatka_do_recenzji()
    problemy = sprawdz_limity(notatka)
    print("--- limity Apple ---")
    if problemy:
        for p in problemy:
            print(f"  PRZEKROCZONY {p}")
        return 1
    print(f"  opis {len(OPIS)}/4000, slowa kluczowe {len(SLOWA_KLUCZOWE)}/100, "
          f"notatka {len(notatka)}/4000 - OK")

    asc = Asc()
    app = asc.aplikacja(BUNDLE_ID)
    if not app:
        raise SystemExit(f"nie ma rekordu aplikacji dla {BUNDLE_ID}")
    aid = app["id"]
    print(f"\n--- aplikacja ---\n  '{app['attributes']['name']}' id={aid}")

    vid, lid = wersja_i_lokalizacja(asc, aid)

    info = asc.get(f"/v1/apps/{aid}/appInfos", **{"limit": 5})["data"][0]
    iid = info["id"]
    print(f"  appInfo id={iid} stan={info['attributes'].get('appStoreState')}")

    if a.pokaz:
        print("\n--- STAN OBECNY (nic nie zmieniam) ---")
        akt = asc.get(f"/v1/appStoreVersionLocalizations/{lid}")["data"]["attributes"]
        for k in ("description", "keywords", "supportUrl", "marketingUrl",
                  "promotionalText", "whatsNew"):
            w = akt.get(k)
            print(f"  {k}: {('(puste)' if not w else str(len(w)) + ' znakow')}")
        ar = pojedynczy(asc, f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        if ar:
            print(f"  App Review notes: {len(ar['attributes'].get('notes') or '')} znakow, "
                  f"kontakt {ar['attributes'].get('contactEmail')}")
        else:
            print("  App Review notes: BRAK (utworze przy --zapisz)")
        ag = pojedynczy(asc, f"/v1/appInfos/{iid}/ageRatingDeclaration")
        print(f"  ageRatingDeclaration: {'id=' + ag['id'] if ag else 'BRAK'}")
        return 0

    # --- 1. teksty karty sklepu ---
    #
    # DWA OSOBNE ZAPISY, i to nie jest ozdoba. 'whatsNew' ("What's New in This
    # Version") jest przy PIERWSZYM wydaniu NIEEDYTOWALNE - Apple odrzuca je z
    # HTTP 409 STATE_ERROR "cannot be edited at this time", bo pole opisuje zmiany
    # wobec poprzedniej wersji, a poprzedniej nie ma. Wrzucone do wspolnego PATCH-a
    # przewracalo CALY zapis: opis i slowa kluczowe tez nie wchodzily, a metadane
    # zostawaly wpisane w POLOWIE. Dlatego pola obowiazkowe leca osobno i pierwsze,
    # a 'whatsNew' jest doproszeniem, ktorego odmowa niczego nie psuje.
    print("\n--- 1. teksty karty sklepu (lokalizacja pl) ---")
    asc.patch(f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
        "type": "appStoreVersionLocalizations", "id": lid,
        "attributes": {
            "description": OPIS,
            "keywords": SLOWA_KLUCZOWE,
            "supportUrl": ADRES_WSPARCIA,
            "marketingUrl": ADRES_WSPARCIA,
        }}})
    print("  wpisane: opis, slowa kluczowe, adres wsparcia, adres marketingowy")
    try:
        asc.patch(f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
            "type": "appStoreVersionLocalizations", "id": lid,
            "attributes": {"whatsNew": CO_NOWEGO}}})
        print("  wpisane: co nowego")
    except BladASC as e:
        if e.status == 409:
            print("  'co nowego' POMINIETE - Apple nie pozwala edytowac tego pola przy")
            print("  pierwszym wydaniu (nie ma poprzedniej wersji). To nie blad.")
        else:
            raise

    # --- 2. wersja: prawa autorskie i tryb wydania ---
    print("\n--- 2. wersja ---")
    asc.patch(f"/v1/appStoreVersions/{vid}", {"data": {
        "type": "appStoreVersions", "id": vid,
        "attributes": {
            "copyright": PRAWA_AUTORSKIE,
            # MANUAL: Michal sam decyduje, kiedy aplikacja pojawi sie w sklepie
            # po zatwierdzeniu. Domyslne AFTER_APPROVAL opublikowaloby ja od razu.
            "releaseType": "MANUAL",
        }}})
    print(f"  prawa autorskie: {PRAWA_AUTORSKIE}")
    print("  tryb wydania: MANUAL (publikacja po zatwierdzeniu na Twoja komende)")

    # --- 3. notatka i kontakt do App Review ---
    print("\n--- 3. App Review Information ---")
    istniejacy = pojedynczy(asc, f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    if istniejacy:
        asc.patch(f"/v1/appStoreReviewDetails/{istniejacy['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": istniejacy["id"],
            "attributes": {**KONTAKT, "notes": notatka}}})
        print(f"  zaktualizowany istniejacy wpis id={istniejacy['id']}")
    else:
        odp = asc.post("/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails",
            "attributes": {**KONTAKT, "notes": notatka},
            "relationships": {"appStoreVersion": {
                "data": {"type": "appStoreVersions", "id": vid}}}}})
        print(f"  utworzony wpis id={odp['data']['id']}")
    print(f"  kontakt: {KONTAKT['contactFirstName']} {KONTAKT['contactLastName']}, "
          f"{KONTAKT['contactEmail']}")
    print(f"  notatka: {len(notatka)} znakow, bez konta demo")

    # --- 4. adresy prywatnosci (na poziomie appInfo, nie wersji) ---
    print("\n--- 4. adres polityki prywatnosci ---")
    lok_info = asc.get(f"/v1/appInfos/{iid}/appInfoLocalizations", **{"limit": 20})
    zrobione = False
    for x in lok_info.get("data", []):
        if x["attributes"]["locale"] == LOCALE:
            asc.patch(f"/v1/appInfoLocalizations/{x['id']}", {"data": {
                "type": "appInfoLocalizations", "id": x["id"],
                "attributes": {"privacyPolicyUrl": ADRES_POLITYKI}}})
            print(f"  wpisany: {ADRES_POLITYKI}")
            zrobione = True
    if not zrobione:
        print(f"  BRAK lokalizacji {LOCALE} w appInfo - adres do wpisania recznie")

    # --- 5. kategoria wiekowa ---
    print("\n--- 5. kategoria wiekowa ---")
    ag = pojedynczy(asc, f"/v1/appInfos/{iid}/ageRatingDeclaration")
    if not ag:
        raise SystemExit("appInfo nie ma ageRatingDeclaration - kategoria wiekowa do wypelnienia recznie")
    asc.patch(f"/v1/ageRatingDeclarations/{ag['id']}",
              {"data": {"type": "ageRatingDeclarations", "id": ag["id"],
                        "attributes": KATEGORIA_WIEKOWA}})
    print(f"  wypelniona (wszystko NONE/false), id={ag['id']}")

    # --- 6. kategorie sklepu ---
    print("\n--- 6. kategorie sklepu ---")
    asc.patch(f"/v1/appInfos/{iid}", {"data": {
        "type": "appInfos", "id": iid,
        "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": KATEGORIA_GLOWNA}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": KATEGORIA_DRUGA}},
        }}})
    print(f"  glowna: {KATEGORIA_GLOWNA}, druga: {KATEGORIA_DRUGA}")

    print("\n=== GOTOWE ===")
    print("Zostaje CZLOWIEKOWI (API tego nie umie): sekcja App Privacy.")
    print("Zrzuty ekranu: tools/wgraj_zrzuty.py")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BladASC as e:
        print(f"\nBLAD API: {e}", file=sys.stderr)
        sys.exit(2)
