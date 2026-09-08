#!/usr/bin/env python3
"""Wystawia App ID, certyfikat dystrybucyjny i profil App Store przez ASC API.

PO CO. Dotychczasowa instrukcja (docs/podpisywanie-ios.md) kazala Michalowi pobrac
z portalu Apple TRZY pliki recznie, w tym walczyc z filtrem wyboru App ID, ktory
nie reaguje na Enter (zmierzona pulapka dostepnosci). Specyfikacja ASC API 4.4.1
ma POST /v1/bundleIds, POST /v1/certificates i POST /v1/profiles - wiec cala ta
czesc jest do zrobienia programowo. Czlowiek musi wygenerowac tylko klucz API.

IDEMPOTENTNIE. Kazdy krok najpierw SPRAWDZA, czy rzecz juz istnieje, i wtedy jej
nie tworzy drugi raz. Powtorne uruchomienie nie zasmieca konta i nie zjada limitu
certyfikatow (Apple ogranicza ich liczbe, a nadmiarowego nie da sie 'cofnac' bez
uniewaznienia).

CO ZAPISUJE na dysk (do katalogu --katalog, domyslnie ~/tyflocentrum-signing):
  distribution.cer      certyfikat w formacie DER - tego oczekuje przygotuj_podpisywanie.py
  TyfloCentrum.mobileprovision   profil App Store

Uzycie:
    python3 tools/wystaw_podpisywanie.py --pokaz        # tylko diagnoza, nic nie tworzy
    python3 tools/wystaw_podpisywanie.py --zapisz       # tworzy brakujace i zapisuje pliki
"""

from __future__ import annotations

import argparse
import base64
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import BUNDLE_ID, TEAM_ID, Asc, BladASC  # noqa: E402

NAZWA_APP_ID = "TyfloCentrum"
NAZWA_PROFILU = "TyfloCentrum App Store"      # zaszyta w .github/workflows/ios-testflight.yml
TYP_CERTYFIKATU = "DISTRIBUTION"              # = 'Apple Distribution'; IOS_DISTRIBUTION to starszy typ
TYP_PROFILU = "IOS_APP_STORE"
KATALOG_DOMYSLNY = os.path.expanduser("~/tyflocentrum-signing")


def wczytaj_csr(katalog: str) -> str:
    """Tresc wniosku o certyfikat. Klucz prywatny NIE opuszcza maszyny - CSR wystarcza."""
    sciezka = os.path.join(katalog, "dist.csr")
    if not os.path.exists(sciezka):
        raise SystemExit(f"brak {sciezka} - to wniosek o certyfikat, bez niego nie ma czego wyslac")
    with open(sciezka) as f:
        return f.read()


def krok_app_id(asc: Asc, zapisz: bool) -> str | None:
    print("--- App ID (bundleIds) ---")
    istniejacy = asc.bundle_id(BUNDLE_ID)
    if istniejacy:
        print(f"  JUZ ISTNIEJE: {BUNDLE_ID} (nazwa '{istniejacy['attributes'].get('name')}', "
              f"id {istniejacy['id']}) - nie tworze drugi raz")
        return istniejacy["id"]
    print(f"  BRAK {BUNDLE_ID}")
    if not zapisz:
        print("  (--pokaz: nie tworze)")
        return None
    odp = asc.post("/v1/bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": BUNDLE_ID,
                "name": NAZWA_APP_ID,
                # UNIVERSAL - tak sa zarejestrowane pozostale App ID w tym koncie
                # i tak dziala profil IOS_APP_STORE dla Sterigo (sprawdzone).
                "platform": "UNIVERSAL",
            },
        }
    })
    nowy = odp["data"]
    print(f"  UTWORZONY: {nowy['attributes']['identifier']} id={nowy['id']}")
    return nowy["id"]


def krok_certyfikat(asc: Asc, katalog: str, zapisz: bool) -> str | None:
    print("\n--- certyfikat dystrybucyjny ---")
    csr = wczytaj_csr(katalog)

    # Czy z TEGO wniosku juz wystawiono certyfikat? Rozstrzyga porownanie klucza
    # publicznego, nie nazwa - ta sama osoba moze miec kilka certyfikatow.
    import subprocess
    def klucz_publiczny_z_csr() -> str | None:
        p = subprocess.run(["openssl", "req", "-in", os.path.join(katalog, "dist.csr"),
                            "-noout", "-pubkey"], capture_output=True)
        return p.stdout.decode() if p.returncode == 0 else None

    nasz_pub = klucz_publiczny_z_csr()
    for c in asc.get("/v1/certificates", **{"limit": 200}).get("data", []):
        at = c["attributes"]
        if at.get("certificateType") != TYP_CERTYFIKATU:
            continue
        try:
            der = base64.b64decode(at["certificateContent"])
            p = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-pubkey"],
                               input=der, capture_output=True)
            if p.returncode == 0 and nasz_pub and p.stdout.decode() == nasz_pub:
                print(f"  JUZ ISTNIEJE certyfikat z NASZEGO wniosku: {at.get('displayName')} "
                      f"(wygasa {at.get('expirationDate')}, id {c['id']}) - nie wystawiam drugiego")
                if zapisz:
                    zapisz_plik(os.path.join(katalog, "distribution.cer"), der)
                return c["id"]
        except Exception:  # noqa: BLE001
            continue

    print(f"  brak certyfikatu {TYP_CERTYFIKATU} pasujacego do naszego dist.csr")
    if not zapisz:
        print("  (--pokaz: nie wystawiam)")
        return None
    try:
        odp = asc.post("/v1/certificates", {
            "data": {
                "type": "certificates",
                "attributes": {"csrContent": csr, "certificateType": TYP_CERTYFIKATU},
            }
        })
    except BladASC as e:
        if "MAXIMUM" in str(e).upper() or "limit" in str(e).lower():
            print(f"  BLAD: Apple odmowilo - prawdopodobnie limit certyfikatow.\n  {e}")
            print("  Wtedy trzeba uniewaznic nieuzywany certyfikat w portalu albo przez API "
                  "(DELETE /v1/certificates/<id>) - ale NIE ten, ktorym podpisano zywa apke.")
        raise
    nowy = odp["data"]
    at = nowy["attributes"]
    print(f"  WYSTAWIONY: {at.get('displayName')} typ={at.get('certificateType')} "
          f"wygasa {at.get('expirationDate')} id={nowy['id']}")
    zapisz_plik(os.path.join(katalog, "distribution.cer"),
                base64.b64decode(at["certificateContent"]))
    return nowy["id"]


def krok_profil(asc: Asc, katalog: str, id_bundle: str | None, id_cert: str | None,
                zapisz: bool) -> str | None:
    print("\n--- profil App Store ---")
    for p in asc.get("/v1/profiles", **{"limit": 200}).get("data", []):
        at = p["attributes"]
        if at.get("name") == NAZWA_PROFILU:
            print(f"  JUZ ISTNIEJE profil '{NAZWA_PROFILU}' [{at.get('profileType')}] "
                  f"{at.get('profileState')} id={p['id']}")
            if at.get("profileState") != "ACTIVE":
                print("  UWAGA: profil NIE jest ACTIVE - do wydania potrzebny aktywny. "
                      "Usun go (DELETE /v1/profiles/<id>) i uruchom ponownie.")
            if zapisz:
                zapisz_plik(os.path.join(katalog, "TyfloCentrum.mobileprovision"),
                            base64.b64decode(at["profileContent"]))
            return p["id"]

    print(f"  brak profilu o nazwie '{NAZWA_PROFILU}'")
    if not zapisz:
        print("  (--pokaz: nie tworze)")
        return None
    if not (id_bundle and id_cert):
        print("  nie mam id App ID albo certyfikatu - profil bez nich nie powstanie")
        return None
    odp = asc.post("/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": NAZWA_PROFILU, "profileType": TYP_PROFILU},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": id_bundle}},
                "certificates": {"data": [{"type": "certificates", "id": id_cert}]},
            },
        }
    })
    nowy = odp["data"]
    at = nowy["attributes"]
    print(f"  UTWORZONY: '{at.get('name')}' [{at.get('profileType')}] {at.get('profileState')} "
          f"wygasa {at.get('expirationDate')} id={nowy['id']}")
    zapisz_plik(os.path.join(katalog, "TyfloCentrum.mobileprovision"),
                base64.b64decode(at["profileContent"]))
    return nowy["id"]


def zapisz_plik(sciezka: str, dane: bytes) -> None:
    with open(sciezka, "wb") as f:
        f.write(dane)
    os.chmod(sciezka, 0o600)
    print(f"  zapisane: {sciezka} ({len(dane)} B)")


def krok_rekord_aplikacji(asc: Asc) -> None:
    """Rekord aplikacji tworzy CZLOWIEK - /v1/apps ma tylko GET. Tu tylko meldujemy stan."""
    print("\n--- rekord aplikacji w App Store Connect ---")
    app = asc.aplikacja(BUNDLE_ID)
    if app:
        at = app["attributes"]
        print(f"  ISTNIEJE: '{at.get('name')}' sku={at.get('sku')} "
              f"jezyk={at.get('primaryLocale')} id={app['id']}")
    else:
        print(f"  NIE ISTNIEJE rekord dla {BUNDLE_ID}.")
        print("  Tego JEDNEGO kroku nie da sie zrobic przez API: /v1/apps ma tylko GET,")
        print("  a Apple pisze wprost, zeby nowych aplikacji nie tworzyc przez API.")
        print("  Zrob to na appstoreconnect.apple.com/apps -> '+' -> New App.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--katalog", default=KATALOG_DOMYSLNY)
    grupa = ap.add_mutually_exclusive_group(required=True)
    grupa.add_argument("--pokaz", action="store_true", help="tylko diagnoza, nic nie tworzy")
    grupa.add_argument("--zapisz", action="store_true", help="tworzy brakujace i zapisuje pliki")
    a = ap.parse_args()

    katalog = os.path.expanduser(a.katalog)
    os.makedirs(katalog, exist_ok=True)
    asc = Asc()
    print(f"konto: team {TEAM_ID}, klucz {asc.key_id}\nkatalog: {katalog}\n")

    id_bundle = krok_app_id(asc, a.zapisz)
    id_cert = krok_certyfikat(asc, katalog, a.zapisz)
    krok_profil(asc, katalog, id_bundle, id_cert, a.zapisz)
    krok_rekord_aplikacji(asc)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BladASC as e:
        print(f"\nBLAD API: {e}", file=sys.stderr)
        sys.exit(2)
