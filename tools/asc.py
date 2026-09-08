#!/usr/bin/env python3
"""Klient App Store Connect API dla TyfloCentrum - uwierzytelnianie JWT ES256.

PO CO OSOBNY MODUL. Wydanie aplikacji to kilkanascie wywolan API w okreslonej
kolejnosci (App ID, certyfikat, profil, metadane wersji, zrzuty, wysylka,
zgloszenie do recenzji). Trzymanie ich w jednym miejscu z JEDNA implementacja
uwierzytelniania i JEDNYM sposobem raportowania bledow oznacza, ze bledna
odpowiedz Apple jest czytelna od razu, a nie po rozszyfrowaniu surowego HTTP.

CZEGO TO API NIE UMIE (zmierzone na oficjalnej specyfikacji 4.4.1, 966 sciezek,
NIE zalozone): utworzenia REKORDU APLIKACJI (/v1/apps ma tylko GET) oraz sekcji
APP PRIVACY (w specyfikacji nie istnieje zaden endpoint deklaracji zbierania
danych). Te dwie rzeczy robi czlowiek na stronie. Wszystko pozostale - w tym
Submit for Review - jest dostepne programowo.

KLUCZ: rola ADMIN, nie App Manager. Klucz App Managera NIE MA dostepu do
Certificates, Identifiers & Profiles, czyli nie wystawi certyfikatu ani profilu.

Uzycie jako narzedzie diagnostyczne:
    python3 tools/asc.py kim-jestem          # czy klucz dziala i co widzi
    python3 tools/asc.py get /v1/apps --filtr bundleId=net.tyflopodcast.tyflocentrum
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BAZA = "https://api.appstoreconnect.apple.com"
KATALOG_KLUCZY = os.path.expanduser("~/tyflocentrum-signing")
ISSUER_DOMYSLNY = "0f77c35e-142b-4a4c-bc9c-4ac4787ae181"
TEAM_ID = "X2FN885LQU"
BUNDLE_ID = "net.tyflopodcast.tyflocentrum"


class BladASC(Exception):
    """Blad zwrocony przez Apple - z czytelna trescia, nie samym kodem HTTP."""

    def __init__(self, status: int, cialo: str, metoda: str, sciezka: str):
        self.status = status
        self.cialo = cialo
        opis = cialo
        try:
            dane = json.loads(cialo)
            czesci = []
            for e in dane.get("errors", []):
                czesci.append(
                    f"[{e.get('status')} {e.get('code')}] {e.get('title')}: {e.get('detail')}"
                    + (f" (pole: {e.get('source', {}).get('pointer') or e.get('source', {}).get('parameter')})"
                       if e.get("source") else "")
                )
            if czesci:
                opis = "\n  ".join(czesci)
        except Exception:  # noqa: BLE001
            pass
        super().__init__(f"{metoda} {sciezka} -> HTTP {status}\n  {opis}")


def _znajdz_klucz() -> tuple[str, str]:
    """Zwraca (key_id, sciezka_do_p8). Key ID czyta z nazwy pliku AuthKey_<ID>.p8."""
    if not os.path.isdir(KATALOG_KLUCZY):
        raise SystemExit(f"brak katalogu {KATALOG_KLUCZY}")
    kandydaci = [n for n in os.listdir(KATALOG_KLUCZY)
                 if n.startswith("AuthKey_") and n.endswith(".p8")]
    if not kandydaci:
        raise SystemExit(
            f"brak pliku AuthKey_*.p8 w {KATALOG_KLUCZY} - to klucz App Store Connect API"
        )
    if len(kandydaci) > 1:
        raise SystemExit(
            f"w {KATALOG_KLUCZY} jest {len(kandydaci)} kluczy: {kandydaci}. "
            "Zostaw jeden, inaczej nie wiadomo, ktorym podpisywac."
        )
    nazwa = kandydaci[0]
    return nazwa[len("AuthKey_"):-3], os.path.join(KATALOG_KLUCZY, nazwa)


def token(issuer_id: str | None = None, waznosc_s: int = 900) -> str:
    """JWT ES256 do ASC API. Apple przyjmuje exp najwyzej 20 minut w przyszlosc."""
    import jwt  # PyJWT jest w systemowym python3

    key_id, sciezka = _znajdz_klucz()
    with open(sciezka) as f:
        prywatny = f.read()
    teraz = int(time.time())
    return jwt.encode(
        {
            "iss": issuer_id or os.environ.get("ASC_ISSUER_ID") or ISSUER_DOMYSLNY,
            "iat": teraz,
            "exp": teraz + waznosc_s,
            "aud": "appstoreconnect-v1",
        },
        prywatny,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class Asc:
    """Cienki klient REST. Jeden token na czas zycia obiektu (waznosc 15 min)."""

    def __init__(self, issuer_id: str | None = None):
        self.issuer_id = issuer_id or os.environ.get("ASC_ISSUER_ID") or ISSUER_DOMYSLNY
        self.key_id, _ = _znajdz_klucz()
        self._token = token(self.issuer_id)
        self._token_do = time.time() + 800

    def _naglowki(self) -> dict[str, str]:
        if time.time() > self._token_do:
            self._token = token(self.issuer_id)
            self._token_do = time.time() + 800
        return {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json",
        }

    def zawolaj(self, metoda: str, sciezka: str, cialo: dict | None = None,
                parametry: dict | None = None) -> dict:
        url = BAZA + sciezka
        if parametry:
            url += "?" + urllib.parse.urlencode(parametry)
        dane = json.dumps(cialo).encode() if cialo is not None else None
        req = urllib.request.Request(url, data=dane, method=metoda, headers=self._naglowki())
        try:
            with urllib.request.urlopen(req, timeout=90) as odp:
                tresc = odp.read().decode()
                return json.loads(tresc) if tresc.strip() else {"_status": odp.status}
        except urllib.error.HTTPError as e:
            raise BladASC(e.code, e.read().decode("utf-8", "replace"), metoda, sciezka) from None

    def get(self, sciezka: str, **parametry) -> dict:
        return self.zawolaj("GET", sciezka, parametry=parametry or None)

    def post(self, sciezka: str, cialo: dict) -> dict:
        return self.zawolaj("POST", sciezka, cialo=cialo)

    def patch(self, sciezka: str, cialo: dict) -> dict:
        return self.zawolaj("PATCH", sciezka, cialo=cialo)

    def delete(self, sciezka: str) -> dict:
        return self.zawolaj("DELETE", sciezka)

    # --- pomocnicze, uzywane przez kolejne kroki wydania ---

    def aplikacja(self, bundle_id: str = BUNDLE_ID) -> dict | None:
        """Rekord aplikacji albo None. None NIE znaczy 'blad' - rekord tworzy czlowiek."""
        d = self.get("/v1/apps", **{"filter[bundleId]": bundle_id})
        dane = d.get("data") or []
        return dane[0] if dane else None

    def bundle_id(self, identyfikator: str = BUNDLE_ID) -> dict | None:
        d = self.get("/v1/bundleIds", **{"filter[identifier]": identyfikator, "limit": 200})
        for b in d.get("data", []):
            if b["attributes"]["identifier"] == identyfikator:
                return b
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    pod = ap.add_subparsers(dest="cmd", required=True)
    pod.add_parser("kim-jestem", help="sprawdza, czy klucz dziala i co widzi")
    g = pod.add_parser("get", help="dowolny GET")
    g.add_argument("sciezka")
    g.add_argument("--filtr", action="append", default=[], help="klucz=wartosc (moze byc wielokrotnie)")
    a = ap.parse_args()

    asc = Asc()

    if a.cmd == "kim-jestem":
        print(f"key id   : {asc.key_id}")
        print(f"issuer id: {asc.issuer_id}")
        # Kazdy z tych odczytow sprawdza INNE uprawnienie klucza.
        sondy = [
            ("aplikacje (App Store)", "/v1/apps", {"limit": 10}),
            ("certyfikaty (Certificates, Identifiers & Profiles)", "/v1/certificates", {"limit": 10}),
            ("App ID (bundleIds)", "/v1/bundleIds", {"limit": 200}),
            ("profile", "/v1/profiles", {"limit": 10}),
        ]
        bledy = 0
        for opis, sciezka, par in sondy:
            try:
                d = asc.get(sciezka, **par)
                n = len(d.get("data", []))
                print(f"  OK   {opis}: {n} pozycji")
                if sciezka == "/v1/apps":
                    for x in d.get("data", []):
                        print(f"         - {x['attributes'].get('bundleId')} "
                              f"({x['attributes'].get('name')}) id={x['id']}")
                if sciezka == "/v1/certificates":
                    for x in d.get("data", []):
                        at = x["attributes"]
                        print(f"         - {at.get('certificateType')} {at.get('displayName')} "
                              f"wygasa {at.get('expirationDate')}")
                if sciezka == "/v1/bundleIds":
                    for x in d.get("data", []):
                        if "tyflocentrum" in x["attributes"]["identifier"].lower():
                            print(f"         - {x['attributes']['identifier']} "
                                  f"({x['attributes'].get('name')}) id={x['id']}")
                if sciezka == "/v1/profiles":
                    for x in d.get("data", []):
                        at = x["attributes"]
                        print(f"         - {at.get('name')} [{at.get('profileType')}] "
                              f"{at.get('profileState')}")
            except BladASC as e:
                bledy += 1
                print(f"  BLAD {opis}: {e}")
        if bledy:
            print("\nUWAGA: brak dostepu do czesci zasobow. Najczestsza przyczyna to rola "
                  "klucza App Manager zamiast Admin - App Manager NIE widzi Certificates, "
                  "Identifiers & Profiles.")
            return 1
        return 0

    if a.cmd == "get":
        par = dict(f.split("=", 1) for f in a.filtr)
        par = {(k if k.startswith(("filter[", "limit", "sort", "include", "fields[")) else f"filter[{k}]"): v
               for k, v in par.items()}
        print(json.dumps(asc.get(a.sciezka, **par), indent=2, ensure_ascii=False))
        return 0

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BladASC as e:
        print(f"BLAD API: {e}", file=sys.stderr)
        sys.exit(2)
