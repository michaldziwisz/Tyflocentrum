#!/usr/bin/env python3
"""Wgrywa zrzuty ekranu do karty App Store przez ASC API.

PO CO. Wgranie zrzutow w przegladarce to przeciaganie plikow myszka - czynnosc
z zalozenia niedostepna dla czytnika ekranu. ASC API pozwala to zrobic w calosci
programowo, ale procedura ma TRZY kroki i pominiecie ostatniego zostawia zrzut
w stanie "wgrany, ale nie zatwierdzony" (Apple go wtedy nie pokaze):

  1. POST /v1/appScreenshots  - REZERWACJA miejsca; Apple oddaje uploadOperations
     (adres, metoda, naglowki, offset i dlugosc kazdej porcji),
  2. PUT na kazdy adres z uploadOperations - wlasciwe bajty,
  3. PATCH /v1/appScreenshots/<id> z sourceFileChecksum (MD5) i uploaded=true -
     POTWIERDZENIE. Bez tego kroku plik jest na serwerze, a karta sklepu pusta.

Zrzuty musza lezec w OSOBNYCH zestawach na kazdy typ ekranu (appScreenshotSets),
bo Apple wymaga innych wymiarow dla iPhone'a i iPada.

Uzycie:
    python3 tools/wgraj_zrzuty.py --katalog /tmp/zrzuty-asc/pliki --pokaz
    python3 tools/wgraj_zrzuty.py --katalog /tmp/zrzuty-asc/pliki --zapisz
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import BUNDLE_ID, Asc, BladASC  # noqa: E402

LOCALE = "pl"

# Typ zestawu zalezy od WYMIAROW pliku, nie od nazwy. Tabela wg wymogow Apple:
# 1320x2868 = iPhone 6.9" (16 Pro Max), 2064x2752 = iPad Pro 13".
WYMIARY_NA_TYP = {
    (1320, 2868): "APP_IPHONE_67",   # nazwa Apple dla najwiekszego iPhone'a
    (2868, 1320): "APP_IPHONE_67",
    (2064, 2752): "APP_IPAD_PRO_3GEN_129",
    (2752, 2064): "APP_IPAD_PRO_3GEN_129",
}


def wymiary_png(sciezka: str) -> tuple[int, int]:
    """Szerokosc i wysokosc z naglowka PNG - bez PIL, zeby nie zalezec od bibliotek."""
    with open(sciezka, "rb") as f:
        naglowek = f.read(24)
    if naglowek[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{sciezka} nie jest plikiem PNG")
    return int.from_bytes(naglowek[16:20], "big"), int.from_bytes(naglowek[20:24], "big")


def kolejnosc(nazwa: str) -> tuple[int, str]:
    """Zrzuty maja nazwy 'urzadzenie-N-ekran_...'. N ustala kolejnosc w karcie sklepu."""
    m = re.search(r"urzadzenie-(\d+)", nazwa)
    return (int(m.group(1)) if m else 999, nazwa)


def zbierz(katalog: str) -> dict[str, list[str]]:
    """Grupuje pliki po typie zestawu wynikajacym z wymiarow."""
    grupy: dict[str, list[str]] = {}
    for nazwa in sorted(os.listdir(katalog), key=kolejnosc):
        if not nazwa.lower().endswith(".png"):
            continue
        sciezka = os.path.join(katalog, nazwa)
        w, h = wymiary_png(sciezka)
        typ = WYMIARY_NA_TYP.get((w, h))
        if not typ:
            print(f"  POMINIETY {nazwa}: wymiary {w}x{h} nie odpowiadaja zadnemu "
                  f"znanemu typowi ekranu App Store")
            continue
        grupy.setdefault(typ, []).append(sciezka)
    return grupy


def wyslij_bajty(operacje: list[dict], dane: bytes) -> None:
    """Wysyla porcje pliku pod adresy podane przez Apple.

    Apple potrafi podzielic plik na kilka czesci (offset + length). Wysylanie
    calosci pod pierwszy adres 'dziala' dla malych plikow i cicho psuje duze,
    dlatego szanujemy podzial, nawet gdy porcja jest jedna.
    """
    for op in operacje:
        offset = op["offset"]
        dlugosc = op["length"]
        req = urllib.request.Request(
            op["url"], data=dane[offset:offset + dlugosc], method=op["method"])
        for n in op.get("requestHeaders", []):
            req.add_header(n["name"], n["value"])
        with urllib.request.urlopen(req, timeout=180) as odp:
            if odp.status not in (200, 201, 204):
                raise SystemExit(f"upload porcji zwrocil HTTP {odp.status}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--katalog", required=True)
    grupa = ap.add_mutually_exclusive_group(required=True)
    grupa.add_argument("--pokaz", action="store_true")
    grupa.add_argument("--zapisz", action="store_true")
    a = ap.parse_args()

    katalog = os.path.expanduser(a.katalog)
    asc = Asc()
    app = asc.aplikacja(BUNDLE_ID)
    if not app:
        raise SystemExit(f"brak rekordu aplikacji dla {BUNDLE_ID}")
    aid = app["id"]

    wersja = asc.get(f"/v1/apps/{aid}/appStoreVersions", **{"limit": 5})["data"][0]
    vid = wersja["id"]
    lok = asc.get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations",
                  **{"limit": 20})["data"]
    lid = next(x["id"] for x in lok if x["attributes"]["locale"] == LOCALE)
    print(f"wersja {wersja['attributes']['versionString']} | lokalizacja {LOCALE} id={lid}\n")

    print("--- pliki do wgrania ---")
    grupy = zbierz(katalog)
    for typ, pliki in grupy.items():
        print(f"  {typ}: {len(pliki)}")
        for p in pliki:
            w, h = wymiary_png(p)
            print(f"     {os.path.basename(p)[:52]:54s} {w}x{h}")
    if not grupy:
        raise SystemExit("nie znalazlem zadnych zrzutow o poprawnych wymiarach")

    print("\n--- zestawy JUZ w App Store Connect ---")
    istniejace = {}
    zestawy = asc.get(f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets",
                      **{"limit": 20})
    for z in zestawy.get("data", []):
        typ = z["attributes"]["screenshotDisplayType"]
        ile = len(asc.get(f"/v1/appScreenshotSets/{z['id']}/appScreenshots",
                          **{"limit": 20}).get("data", []))
        istniejace[typ] = z["id"]
        print(f"  {typ}: {ile} zrzutow, id={z['id']}")
    if not istniejace:
        print("  (brak)")

    if a.pokaz:
        print("\n(--pokaz: nic nie wgrywam)")
        return 0

    for typ, pliki in grupy.items():
        print(f"\n=== {typ} ===")
        zid = istniejace.get(typ)
        if zid:
            juz = asc.get(f"/v1/appScreenshotSets/{zid}/appScreenshots",
                          **{"limit": 20}).get("data", [])
            if juz:
                print(f"  zestaw ma juz {len(juz)} zrzutow - POMIJAM, zeby nie dublowac.")
                print(f"  Zeby wgrac od nowa: DELETE /v1/appScreenshotSets/{zid}")
                continue
        else:
            odp = asc.post("/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": typ},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})
            zid = odp["data"]["id"]
            print(f"  utworzony zestaw id={zid}")

        for sciezka in pliki:
            nazwa = os.path.basename(sciezka)
            with open(sciezka, "rb") as f:
                dane = f.read()
            suma = hashlib.md5(dane).hexdigest()  # noqa: S324 - Apple wymaga MD5

            rez = asc.post("/v1/appScreenshots", {"data": {
                "type": "appScreenshots",
                "attributes": {"fileName": nazwa, "fileSize": len(dane)},
                "relationships": {"appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": zid}}}}})
            sid = rez["data"]["id"]
            operacje = rez["data"]["attributes"]["uploadOperations"]
            wyslij_bajty(operacje, dane)

            # KROK, KTORY LATWO POMINAC: bez uploaded=true zrzut nie zostanie uzyty.
            pot = asc.patch(f"/v1/appScreenshots/{sid}", {"data": {
                "type": "appScreenshots", "id": sid,
                "attributes": {"uploaded": True, "sourceFileChecksum": suma}}})
            stan = pot["data"]["attributes"].get("assetDeliveryState", {})
            print(f"  {nazwa[:50]:52s} {len(dane):>8} B  stan: {stan.get('state')}")

    print("\n--- WERYFIKACJA ODCZYTEM ---")
    zestawy = asc.get(f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets",
                      **{"limit": 20})
    for z in zestawy.get("data", []):
        typ = z["attributes"]["screenshotDisplayType"]
        zrzuty = asc.get(f"/v1/appScreenshotSets/{z['id']}/appScreenshots",
                         **{"limit": 20}).get("data", [])
        print(f"  {typ}: {len(zrzuty)} zrzutow")
        for s in zrzuty:
            at = s["attributes"]
            st = (at.get("assetDeliveryState") or {}).get("state")
            bledy = (at.get("assetDeliveryState") or {}).get("errors")
            print(f"     {at.get('fileName')[:50]:52s} {st}"
                  + (f"  BLEDY: {bledy}" if bledy else ""))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BladASC as e:
        print(f"\nBLAD API: {e}", file=sys.stderr)
        sys.exit(2)
    except urllib.error.HTTPError as e:
        print(f"\nBLAD UPLOADU: HTTP {e.code} {e.read().decode('utf-8','replace')[:300]}",
              file=sys.stderr)
        sys.exit(3)
