#!/usr/bin/env python3
"""Odpowiedź na odrzucenie Guideline 2.1 — załącznik z nagraniem + pole Notes.

PO CO. Apple odrzucił 1.0 z „Information Needed" i żąda nagrania ekranu
z fizycznego urządzenia oraz opisu aplikacji. Prosi wprost, żeby te informacje
wpisać TAKŻE w App Review Information -> Notes, „for reference on future
submissions".

CZEGO API NIE UMIE (zmierzone na specyfikacji 4.4.1, 966 sciezek, NIE zalozone):
nie ma ANI JEDNEGO endpointu do korespondencji w Resolution Center - zero sciezek
`resolution`, `correspondence`, `thread`, `reply`. Odpowiedz recenzentowi wkleja
czlowiek w przegladarce. Programowo robimy dwie rzeczy: Notes i zalacznik.

WGRYWANIE ZALACZNIKA jest trzyetapowe i kazdy etap ma wlasny tryb bledu:
  1. POST /v1/appStoreReviewAttachments  -> dostajemy uploadOperations
  2. PUT na URL z uploadOperations       -> surowe bajty, naglowki OD APPLE
  3. PATCH .../{id} uploaded=true + sourceFileChecksum(MD5)
Pominiecie kroku 3 daje zalacznik widoczny w API, ale dla Apple NIEISTNIEJACY.
Dlatego na koncu ZAWSZE odczytujemy assetDeliveryState.

Uzycie:
    python3 tools/odpowiedz_na_odrzucenie.py --pokaz
    python3 tools/odpowiedz_na_odrzucenie.py --zalacznik /sciezka/film.MP4
    python3 tools/odpowiedz_na_odrzucenie.py --notatka docs/app-review-notes-en.md
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from asc import Asc, BladASC  # noqa: E402

BUNDLE_ID = "net.tyflopodcast.tyflocentrum"


def wersja_w_recenzji(asc: Asc, app_id: str) -> dict:
    """Najnowsza wersja aplikacji - tam wisi appStoreReviewDetail."""
    odp = asc.get(f"/v1/apps/{app_id}/appStoreVersions")
    dane = odp.get("data", [])
    if not dane:
        raise SystemExit("BLAD: aplikacja nie ma zadnej wersji")
    return dane[0]


def detal_recenzji(asc: Asc, wersja_id: str) -> dict:
    odp = asc.get(f"/v1/appStoreVersions/{wersja_id}/appStoreReviewDetail")
    dane = odp.get("data")
    if not dane:
        raise SystemExit("BLAD: wersja nie ma appStoreReviewDetail")
    return dane


def md5_pliku(sciezka: Path) -> str:
    h = hashlib.md5()  # noqa: S324 - Apple wymaga MD5, nie nasz wybor
    with sciezka.open("rb") as f:
        for kawalek in iter(lambda: f.read(1024 * 1024), b""):
            h.update(kawalek)
    return h.hexdigest()


def pokaz(asc: Asc) -> int:
    app = asc.aplikacja(BUNDLE_ID)
    if app is None:
        print(f"BLAD: brak rekordu aplikacji {BUNDLE_ID}")
        return 1
    app_id = app["id"]
    w = wersja_w_recenzji(asc, app_id)
    wa = w["attributes"]
    print(f"wersja    : {wa.get('versionString')} stan={wa.get('appStoreState')} id={w['id']}")

    zgloszenia = asc.get(f"/v1/apps/{app_id}/reviewSubmissions").get("data", [])
    for z in zgloszenia:
        za = z["attributes"]
        print(f"zgloszenie: {z['id']} stan={za.get('state')} wyslane={za.get('submittedDate')}")

    detal = detal_recenzji(asc, w["id"])
    print(f"detal     : {detal['id']}")
    notatka = detal["attributes"].get("notes") or ""
    print(f"notatka   : {len(notatka)} znakow (limit Apple 4000)")

    zal = asc.get(f"/v1/appStoreReviewDetails/{detal['id']}/appStoreReviewAttachments")
    dane = zal.get("data", [])
    if not dane:
        print("zalaczniki: BRAK")
    for a in dane:
        aa = a["attributes"]
        print(
            f"zalacznik : {a['id']} {aa.get('fileName')} "
            f"{aa.get('fileSize')} B stan={aa.get('assetDeliveryState', {}).get('state')}"
        )
    return 0


def wgraj_zalacznik(asc: Asc, sciezka: Path) -> int:
    if not sciezka.is_file():
        print(f"BLAD: nie ma pliku {sciezka}")
        return 1
    rozmiar = sciezka.stat().st_size
    suma = md5_pliku(sciezka)
    print(f"plik      : {sciezka.name} {rozmiar} B md5={suma}")

    app = asc.aplikacja(BUNDLE_ID)
    if app is None:
        print(f"BLAD: brak rekordu aplikacji {BUNDLE_ID}")
        return 1
    w = wersja_w_recenzji(asc, app["id"])
    detal = detal_recenzji(asc, w["id"])

    print("krok 1/3  : rezerwacja zasobu")
    odp = asc.post(
        "/v1/appStoreReviewAttachments",
        {
            "data": {
                "type": "appStoreReviewAttachments",
                "attributes": {"fileName": sciezka.name, "fileSize": rozmiar},
                "relationships": {
                    "appStoreReviewDetail": {
                        "data": {"type": "appStoreReviewDetails", "id": detal["id"]}
                    }
                },
            }
        },
    )
    zasob = odp["data"]
    operacje = zasob["attributes"].get("uploadOperations") or []
    if not operacje:
        print("BLAD: Apple nie zwrocil uploadOperations")
        return 1
    print(f"            id={zasob['id']}, operacji={len(operacje)}")

    dane = sciezka.read_bytes()
    for i, op in enumerate(operacje, 1):
        offset = op.get("offset", 0)
        dlugosc = op.get("length", len(dane))
        kawalek = dane[offset : offset + dlugosc]
        naglowki = {h["name"]: h["value"] for h in (op.get("requestHeaders") or [])}
        req = urllib.request.Request(
            op["url"], data=kawalek, method=op.get("method", "PUT"), headers=naglowki
        )
        try:
            with urllib.request.urlopen(req, timeout=900) as r:  # noqa: S310
                print(f"krok 2/3  : czesc {i}/{len(operacje)} HTTP {r.status} ({dlugosc} B)")
        except urllib.error.HTTPError as e:
            print(f"BLAD wgrywania czesci {i}: HTTP {e.code} {e.read()[:300]!r}")
            return 1

    print("krok 3/3  : domkniecie (uploaded=true + suma kontrolna)")
    asc.patch(
        f"/v1/appStoreReviewAttachments/{zasob['id']}",
        {
            "data": {
                "type": "appStoreReviewAttachments",
                "id": zasob["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": suma},
            }
        },
    )

    # ODCZYT PO ZMIANIE - bez tego nie wiemy, czy Apple przyjal plik
    stan = asc.get(f"/v1/appStoreReviewAttachments/{zasob['id']}")
    dostawa = stan["data"]["attributes"].get("assetDeliveryState") or {}
    print(f"stan      : {dostawa.get('state')} bledy={dostawa.get('errors')}")
    if dostawa.get("state") not in ("COMPLETE", "UPLOAD_COMPLETE"):
        print("UWAGA: stan nie jest COMPLETE - Apple moze jeszcze przetwarzac plik")
    return 0


def ustaw_notatke(asc: Asc, sciezka: Path) -> int:
    if not sciezka.is_file():
        print(f"BLAD: nie ma pliku {sciezka}")
        return 1
    tresc = sciezka.read_text(encoding="utf-8").strip()
    if len(tresc) > 4000:
        print(f"BLAD: notatka ma {len(tresc)} znakow, limit Apple to 4000")
        return 1

    app = asc.aplikacja(BUNDLE_ID)
    if app is None:
        print(f"BLAD: brak rekordu aplikacji {BUNDLE_ID}")
        return 1
    w = wersja_w_recenzji(asc, app["id"])
    detal = detal_recenzji(asc, w["id"])

    asc.patch(
        f"/v1/appStoreReviewDetails/{detal['id']}",
        {
            "data": {
                "type": "appStoreReviewDetails",
                "id": detal["id"],
                "attributes": {"notes": tresc},
            }
        },
    )
    po = asc.get(f"/v1/appStoreReviewDetails/{detal['id']}")
    zapisane = po["data"]["attributes"].get("notes") or ""
    if zapisane.strip() != tresc:
        print(f"BLAD: odczyt po zapisie sie NIE zgadza ({len(zapisane)} vs {len(tresc)})")
        return 1
    print(f"notatka zapisana i POTWIERDZONA ODCZYTEM: {len(zapisane)} znakow")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--pokaz", action="store_true", help="diagnoza, nic nie zmienia")
    g.add_argument("--zalacznik", metavar="PLIK", help="wgrywa nagranie do App Review")
    g.add_argument("--notatka", metavar="PLIK", help="ustawia pole Notes z pliku tekstowego")
    args = p.parse_args()

    asc = Asc()
    try:
        if args.pokaz:
            return pokaz(asc)
        if args.zalacznik:
            return wgraj_zalacznik(asc, Path(args.zalacznik))
        return ustaw_notatke(asc, Path(args.notatka))
    except BladASC as e:
        print(f"BLAD ASC: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
