#!/usr/bin/env python3
"""Wydanie NOWEJ wersji aplikacji iOS do App Store: od utworzenia wersji do
zgloszenia jej do recenzji.

PO CO OSOBNE NARZEDZIE. `metadane_wydania.py` uzupelnia teksty ISTNIEJACEJ
wersji. Tu chodzi o pelny cykl aktualizacji, ktory ma cztery kroki i kazdy
potrafi paść osobno:

  1. POST /v1/appStoreVersions          - utworzenie rekordu wersji (np. 1.0.1)
  2. PATCH localization                 - "Co nowego w tej wersji"
  3. PATCH build                         - przypiecie zbudowanego builda
  4. POST /v1/reviewSubmissionItems      - zgloszenie do recenzji Apple

Domyslnie narzedzie tylko CZYTA i pokazuje, co by zrobilo. Kazdy krok
zmieniajacy stan w koncie Apple wymaga jawnego --zapisz.

UWAGA na krok 4: pustego `reviewSubmissions` Apple NIE POZWALA usunac. Dlatego
zgloszenie tworzymy dopiero, gdy wersja ma build i teksty, a --zapisz podano
swiadomie.

Uzycie:
    python3 tools/wydaj_wersje.py --pokaz
    python3 tools/wydaj_wersje.py --zapisz
    python3 tools/wydaj_wersje.py --zapisz --bez-zgloszenia   # bez kroku 4
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from asc import Asc  # noqa: E402

APLIKACJA = "6809841876"
WERSJA = "1.0.1"
NUMER_BUILDA = "2"

CO_NOWEGO = """Nowe treści dociągają się teraz po powrocie do aplikacji z przełącznika \
aplikacji. Dotąd zdarzało się, że lista zostawała nieodświeżona, dopóki aplikacja nie \
została uruchomiona od nowa.

Nowe wpisy dokładają się nad dotychczasowymi, bez zmiany miejsca czytania: VoiceOver \
nie gubi pozycji ani fokusu, a o liczbie nowych treści informuje komunikat.

Odświeżanie jest oszczędne dla baterii — pobiera dane tylko wtedy, gdy są starsze niż \
dwie minuty, i nic nie robi w tle.

Poprawione też ręczne odświeżanie listy: mogło wcześniej pokazać dane z pamięci \
zamiast pobrać nowe."""

LIMIT_CO_NOWEGO = 4000


def pojedynczy(asc: Asc, sciezka: str, **filtry) -> dict | None:
    dane = asc.get(sciezka, **filtry).get("data") or []
    return dane[0] if dane else None


def znajdz_wersje(asc: Asc, wersja: str) -> dict | None:
    """Szuka rekordu wersji po numerze. Wersja moze juz istniec z poprzedniego
    uruchomienia - wtedy jej NIE tworzymy drugi raz."""
    dane = asc.get(f"/v1/apps/{APLIKACJA}/appStoreVersions", limit=20).get("data") or []
    for w in dane:
        if w["attributes"].get("versionString") == wersja:
            return w
    return None


def znajdz_build(asc: Asc, numer: str) -> dict | None:
    dane = asc.get("/v1/builds", **{"filter[app]": APLIKACJA}).get("data") or []
    for b in dane:
        if b["attributes"].get("version") == numer:
            return b
    return None


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    grupa = ap.add_mutually_exclusive_group(required=True)
    grupa.add_argument("--pokaz", action="store_true", help="diagnoza, nic nie zmienia")
    grupa.add_argument("--zapisz", action="store_true", help="wykonuje zmiany w ASC")
    ap.add_argument(
        "--bez-zgloszenia",
        action="store_true",
        help="pomin krok 4 (zgloszenie do recenzji Apple)",
    )
    args = ap.parse_args()

    if len(CO_NOWEGO) > LIMIT_CO_NOWEGO:
        print(
            f"BLAD: 'Co nowego' ma {len(CO_NOWEGO)} znakow, limit {LIMIT_CO_NOWEGO}",
            file=sys.stderr,
        )
        return 1
    print(f"'Co nowego': {len(CO_NOWEGO)} znakow (limit {LIMIT_CO_NOWEGO}) OK")

    asc = Asc()

    # --- Krok 0: stan wyjsciowy ---
    build = znajdz_build(asc, NUMER_BUILDA)
    if not build:
        print(f"BLAD: nie znalazlem builda {NUMER_BUILDA}", file=sys.stderr)
        return 1
    stan_builda = build["attributes"].get("processingState")
    print(f"build {NUMER_BUILDA}: {stan_builda} (id {build['id']})")
    if stan_builda != "VALID":
        print("BLAD: build nie jest VALID, nie ma czego przypinac", file=sys.stderr)
        return 1

    wersja = znajdz_wersje(asc, WERSJA)
    if wersja:
        print(
            f"wersja {WERSJA} JUZ ISTNIEJE: {wersja['attributes'].get('appStoreState')} "
            f"(id {wersja['id']})"
        )
    else:
        print(f"wersja {WERSJA}: nie istnieje, do utworzenia")

    if args.pokaz:
        print("\n--pokaz: nic nie zmieniam. Kroki do wykonania przy --zapisz:")
        if not wersja:
            print(f"  1. utworzyc wersje {WERSJA} (platform IOS)")
        print("  2. wpisac 'Co nowego' do lokalizacji pl-PL")
        print(f"  3. przypiac build {NUMER_BUILDA}")
        if not args.bez_zgloszenia:
            print("  4. zglosic wersje do recenzji Apple")
        return 0

    # --- Krok 1: utworzenie wersji ---
    if not wersja:
        odp = asc.post(
            "/v1/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": WERSJA},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APLIKACJA}}
                    },
                }
            },
        )
        wersja = odp["data"]
        print(f"KROK 1 OK: utworzona wersja {WERSJA}, id {wersja['id']}")

    id_wersji = wersja["id"]

    # --- Krok 2: 'Co nowego' ---
    lok = pojedynczy(asc, f"/v1/appStoreVersions/{id_wersji}/appStoreVersionLocalizations")
    if not lok:
        print("BLAD: brak lokalizacji do uzupelnienia", file=sys.stderr)
        return 1
    asc.patch(
        f"/v1/appStoreVersionLocalizations/{lok['id']}",
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": lok["id"],
                "attributes": {"whatsNew": CO_NOWEGO},
            }
        },
    )
    print(f"KROK 2 OK: 'Co nowego' wpisane ({lok['attributes'].get('locale')})")

    # --- Krok 3: przypiecie builda ---
    asc.patch(
        f"/v1/appStoreVersions/{id_wersji}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": id_wersji,
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build["id"]}}
                },
            }
        },
    )
    print(f"KROK 3 OK: przypiety build {NUMER_BUILDA}")

    if args.bez_zgloszenia:
        print("\n--bez-zgloszenia: wersja gotowa, ale NIE zgloszona do recenzji.")
        return 0

    # --- Krok 4: zgloszenie do recenzji ---
    # Zgloszenie moze juz istniec (np. z poprzedniej proby) - wtedy dodajemy
    # do niego pozycje, zamiast tworzyc drugie (Apple nie pozwala go usunac).
    zgl = None
    for kandydat in asc.get(
        f"/v1/apps/{APLIKACJA}/reviewSubmissions", limit=10
    ).get("data") or []:
        if kandydat["attributes"].get("state") in {
            "READY_FOR_REVIEW",
            "UNRESOLVED_ISSUES",
        }:
            zgl = kandydat
            break

    if zgl:
        print(f"zgloszenie istnieje: {zgl['attributes'].get('state')} (id {zgl['id']})")
    else:
        odp = asc.post(
            "/v1/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APLIKACJA}}
                    },
                }
            },
        )
        zgl = odp["data"]
        print(f"KROK 4a OK: utworzone zgloszenie, id {zgl['id']}")

    asc.post(
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": zgl["id"]}
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": id_wersji}
                    },
                },
            }
        },
    )
    print("KROK 4b OK: wersja dodana do zgloszenia")

    asc.patch(
        f"/v1/reviewSubmissions/{zgl['id']}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": zgl["id"],
                "attributes": {"submitted": True},
            }
        },
    )
    print("KROK 4c OK: zgloszenie wyslane do Apple")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
