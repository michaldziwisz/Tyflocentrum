#!/usr/bin/env python3
"""Wewnętrzna grupa TestFlight dla TyfloCentrum — instalacja buildu na telefonie
bez Beta App Review.

PO CO TO ISTNIEJE. Apple odrzucił 1.0 z Guideline 2.1 „Information Needed” i żąda
nagrania ekranu z FIZYCZNEGO urządzenia. Żeby takie nagranie powstało, aplikacja
musi być na telefonie — a jedyna droga bez Maca to TestFlight. Grupa WEWNĘTRZNA
(`isInternalGroup=true`) przyjmuje wyłącznie użytkowników App Store Connect
i dlatego NIE przechodzi Beta App Review: build jest do zainstalowania od razu
po przypięciu. Grupa zewnętrzna wymagałaby recenzji, czyli kolejnego czekania.

CZEGO TO NARZĘDZIE NIE ROBI: nie tworzy grup zewnętrznych ani publicznych linków.
Świadomie — wersja, która nie przeszła recenzji App Store, nie ma trafiać do
osób z zewnątrz.

Użycie:
    python3 tools/testflight_wewnetrzny.py --pokaz     # diagnoza, NIC nie zmienia
    python3 tools/testflight_wewnetrzny.py --zapisz    # grupa + tester + build
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from asc import Asc, BladASC  # noqa: E402

BUNDLE_ID = "net.tyflopodcast.tyflocentrum"
NAZWA_GRUPY = "Wewnetrzni (nagrania i testy)"


def znajdz_grupe(asc: Asc, app_id: str) -> dict | None:
    """Zwraca naszą grupę wewnętrzną, jeśli już istnieje (idempotencja)."""
    odp = asc.get(f"/v1/apps/{app_id}/betaGroups")
    for grupa in odp.get("data", []):
        if grupa["attributes"].get("name") == NAZWA_GRUPY:
            return grupa
    return None


def najnowszy_build(asc: Asc, app_id: str) -> dict | None:
    """Najświeższy build nadający się do rozdania (VALID, nie wygasły)."""
    odp = asc.get("/v1/builds", **{"filter[app]": app_id})
    zdatne = [
        b
        for b in odp.get("data", [])
        if b["attributes"].get("processingState") == "VALID"
        and not b["attributes"].get("expired")
    ]
    if not zdatne:
        return None
    # uploadedDate jest w ISO 8601 z offsetem, więc sortowanie leksykalne
    # NIE jest poprawne (różne offsety); porównujemy po dacie z parsowania.
    from datetime import datetime

    def kiedy(b: dict) -> datetime:
        return datetime.fromisoformat(b["attributes"]["uploadedDate"])

    return max(zdatne, key=kiedy)


def uzytkownicy(asc: Asc) -> list[dict]:
    return asc.get("/v1/users").get("data", [])


def pokaz(asc: Asc) -> int:
    app = asc.aplikacja(BUNDLE_ID)
    if app is None:
        print(f"BLAD: nie ma rekordu aplikacji dla {BUNDLE_ID}")
        return 1
    app_id = app["id"]
    print(f"aplikacja : {app['attributes'].get('name')} id={app_id}")

    grupa = znajdz_grupe(asc, app_id)
    if grupa is None:
        print(f"grupa     : BRAK (utworzy: {NAZWA_GRUPY!r}, wewnetrzna)")
    else:
        a = grupa["attributes"]
        print(
            f"grupa     : JEST id={grupa['id']} wewnetrzna={a.get('isInternalGroup')} "
            f"wszystkie_buildy={a.get('hasAccessToAllBuilds')}"
        )
        testerzy = asc.get(f"/v1/betaGroups/{grupa['id']}/betaTesters").get("data", [])
        for t in testerzy:
            ta = t["attributes"]
            print(f"  tester  : {ta.get('email')} state={ta.get('state')}")
        buildy = asc.get(f"/v1/betaGroups/{grupa['id']}/builds").get("data", [])
        for b in buildy:
            print(f"  build   : {b['id']} ver={b['attributes'].get('version')}")

    b = najnowszy_build(asc, app_id)
    if b is None:
        print("build     : BRAK zdatnego (VALID, niewygasly)")
        return 1
    print(
        f"build     : {b['id']} ver={b['attributes'].get('version')} "
        f"wygasa={b['attributes'].get('expirationDate')}"
    )

    for u in uzytkownicy(asc):
        ua = u["attributes"]
        print(f"uzytkownik: {ua.get('username')} role={ua.get('roles')}")
    return 0


def zapisz(asc: Asc) -> int:
    app = asc.aplikacja(BUNDLE_ID)
    if app is None:
        print(f"BLAD: nie ma rekordu aplikacji dla {BUNDLE_ID}")
        return 1
    app_id = app["id"]

    grupa = znajdz_grupe(asc, app_id)
    if grupa is None:
        odp = asc.post(
            "/v1/betaGroups",
            {
                "data": {
                    "type": "betaGroups",
                    "attributes": {
                        "name": NAZWA_GRUPY,
                        "isInternalGroup": True,
                        "hasAccessToAllBuilds": True,
                        # jawnie WYLACZONE: wersja bez recenzji App Store nie
                        # ma byc dostepna z linku publicznego
                        "publicLinkEnabled": False,
                        "feedbackEnabled": True,
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}}
                    },
                }
            },
        )
        grupa = odp["data"]
        print(f"UTWORZONA grupa {grupa['id']} {NAZWA_GRUPY!r} (wewnetrzna)")
    else:
        print(f"grupa juz istnieje: {grupa['id']}")
    grupa_id = grupa["id"]

    # testerzy: wszyscy uzytkownicy konta (grupa wewnetrzna innych nie przyjmie)
    obecni = {
        t["attributes"].get("email", "").lower()
        for t in asc.get(f"/v1/betaGroups/{grupa_id}/betaTesters").get("data", [])
    }
    for u in uzytkownicy(asc):
        ua = u["attributes"]
        mail = (ua.get("username") or "").lower()
        if not mail or mail in obecni:
            print(f"tester juz w grupie: {mail}")
            continue
        try:
            asc.post(
                "/v1/betaTesters",
                {
                    "data": {
                        "type": "betaTesters",
                        "attributes": {
                            "firstName": ua.get("firstName"),
                            "lastName": ua.get("lastName"),
                            "email": mail,
                        },
                        "relationships": {
                            "betaGroups": {
                                "data": [{"type": "betaGroups", "id": grupa_id}]
                            }
                        },
                    }
                },
            )
            print(f"DODANY tester: {mail}")
        except BladASC as e:
            # tester moze istniec w koncie, ale poza grupa - wtedy tylko linkujemy
            print(f"  post /v1/betaTesters odmowil ({e.status}), probuje linkowanie")
            wszyscy = asc.get("/v1/betaTesters").get("data", [])
            trafiony = next(
                (
                    t
                    for t in wszyscy
                    if (t["attributes"].get("email") or "").lower() == mail
                ),
                None,
            )
            if trafiony is None:
                print(f"  BLAD: nie znalazlem testera {mail} w koncie")
                return 1
            asc.post(
                f"/v1/betaGroups/{grupa_id}/relationships/betaTesters",
                {"data": [{"type": "betaTesters", "id": trafiony["id"]}]},
            )
            print(f"DOLINKOWANY tester: {mail}")

    b = najnowszy_build(asc, app_id)
    if b is None:
        print("BLAD: brak zdatnego buildu do przypiecia")
        return 1
    przypiete = {
        x["id"] for x in asc.get(f"/v1/betaGroups/{grupa_id}/builds").get("data", [])
    }
    if b["id"] in przypiete:
        print(f"build juz przypiety: {b['id']}")
    else:
        asc.post(
            f"/v1/betaGroups/{grupa_id}/relationships/builds",
            {"data": [{"type": "builds", "id": b["id"]}]},
        )
        print(f"PRZYPIETY build {b['id']} ver={b['attributes'].get('version')}")

    print()
    print("ODCZYT PO ZMIANIE (dowod, nie zalozenie):")
    return pokaz(asc)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--pokaz", action="store_true", help="diagnoza, nic nie zmienia")
    g.add_argument("--zapisz", action="store_true", help="tworzy grupe, testera, przypina build")
    args = p.parse_args()

    asc = Asc()
    try:
        return pokaz(asc) if args.pokaz else zapisz(asc)
    except BladASC as e:
        print(f"BLAD ASC: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
