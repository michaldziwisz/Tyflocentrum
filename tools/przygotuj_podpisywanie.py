#!/usr/bin/env python3
"""Przetwarza pliki podpisujace od Apple i ustawia sekrety w GitHubie.

PO CO. Po tym, jak Michal pobierze z portalu Apple trzy pliki (certyfikat, profil,
klucz API), reszta jest mechaniczna: sprawdzic zgodnosc, zlozyc .p12, zakodowac
base64, wpisac 7 sekretow. Recznie to kilkanascie polecen, w ktorych latwo o pomylke
niewychodzaca na jaw az do padniecia buildu.

CO SPRAWDZA PRZED USTAWIENIEM SEKRETOW (kolejnosc = od najtanszego bledu):
  1. czy wszystkie trzy pliki sa na miejscu,
  2. czy certyfikat PASUJE do naszego klucza prywatnego (porownanie modulow) -
     to najczestszy blad: certyfikat wystawiony na inny CSR wyglada poprawnie,
     a podpisywanie pada dopiero na runnerze,
  3. czy certyfikat to naprawde Apple Distribution i czy Team ID sie zgadza,
  4. czy profil dotyczy net.tyflocentrum.app,
  5. czy profil jest App Store, a nie deweloperski (get-task-allow musi byc false),
  6. czy profil nie ma listy urzadzen (to znak profilu deweloperskiego).

Uzycie:
    python3 tools/przygotuj_podpisywanie.py --katalog /mnt/c/Users/m/Downloads/tyflocentrum-signing \\
        --key-id ABC123DEFG --issuer-id 0f77c35e-...

    Dodaj --tylko-sprawdz, zeby zweryfikowac pliki BEZ ustawiania sekretow.
"""

from __future__ import annotations

import argparse
import base64
import glob
import os
import plistlib
import secrets
import string
import subprocess
import sys
import tempfile

TEAM_ID = "X2FN885LQU"
BUNDLE_ID = "net.tyflocentrum.app"
REPO = "michaldziwisz/Tyflocentrum"
KLUCZ_PRYWATNY = os.path.expanduser("~/tyflocentrum-signing/dist.key")

bledy: list[str] = []
ostrzezenia: list[str] = []


def uruchom(cmd: list[str], wejscie: bytes | None = None) -> tuple[int, str]:
    """Uruchamia polecenie i zwraca (kod, wyjscie). Nie rzuca wyjatkiem."""
    p = subprocess.run(cmd, input=wejscie, capture_output=True)
    return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")


def znajdz(katalog: str, wzorce: list[str], opis: str) -> str | None:
    for w in wzorce:
        trafienia = sorted(glob.glob(os.path.join(katalog, w)))
        if trafienia:
            return trafienia[0]
    bledy.append(f"brak pliku: {opis} (szukalem {', '.join(wzorce)})")
    return None


def modul(cmd: list[str]) -> str | None:
    """Modul RSA jako skrot - do porownania klucza z certyfikatem."""
    kod, out = uruchom(cmd)
    if kod != 0:
        return None
    for linia in out.splitlines():
        if linia.startswith("Modulus="):
            return linia.split("=", 1)[1].strip()
    return None


def sprawdz_certyfikat(cer: str, tmp: str) -> str | None:
    """Konwertuje .cer na PEM i weryfikuje. Zwraca sciezke do PEM albo None."""
    crt = os.path.join(tmp, "dist.crt")
    kod, out = uruchom(["openssl", "x509", "-inform", "DER", "-in", cer, "-out", crt])
    if kod != 0:
        # Apple czasem oddaje juz PEM - probujemy drugiego formatu.
        kod, out = uruchom(["openssl", "x509", "-in", cer, "-out", crt])
        if kod != 0:
            bledy.append(f"nie moge odczytac certyfikatu {os.path.basename(cer)}: {out.strip()[:200]}")
            return None

    kod, subject = uruchom(["openssl", "x509", "-in", crt, "-noout", "-subject"])
    print(f"  certyfikat: {subject.strip()}")

    if "Apple Distribution" not in subject:
        bledy.append(
            "certyfikat NIE jest typu 'Apple Distribution' - do App Store potrzebny "
            f"wlasnie ten typ (jest: {subject.strip()})"
        )
    if TEAM_ID not in subject:
        bledy.append(f"certyfikat nie zawiera naszego Team ID {TEAM_ID} - czy powstal w Twoim zespole?")

    if not os.path.exists(KLUCZ_PRYWATNY):
        bledy.append(f"brak klucza prywatnego {KLUCZ_PRYWATNY} - bez niego .p12 nie powstanie")
        return crt

    m_klucz = modul(["openssl", "rsa", "-in", KLUCZ_PRYWATNY, "-noout", "-modulus"])
    m_cert = modul(["openssl", "x509", "-in", crt, "-noout", "-modulus"])
    if m_klucz is None or m_cert is None:
        ostrzezenia.append("nie udalo sie porownac klucza z certyfikatem")
    elif m_klucz != m_cert:
        bledy.append(
            "CERTYFIKAT NIE PASUJE DO KLUCZA PRYWATNEGO. Prawdopodobnie powstal "
            "z innego wniosku (CSR). Wygeneruj certyfikat ponownie z dist.csr."
        )
    else:
        print("  klucz prywatny pasuje do certyfikatu")
    return crt


def sprawdz_profil(profil: str) -> None:
    kod, out = uruchom(["openssl", "smime", "-inform", "DER", "-verify", "-noverify", "-in", profil])
    if kod != 0:
        bledy.append(f"nie moge odczytac profilu: {out.strip()[:200]}")
        return
    try:
        dane = plistlib.loads(out.encode("utf-8", "surrogateescape"))
    except Exception as e:  # noqa: BLE001
        bledy.append(f"profil nie jest poprawnym plist: {e}")
        return

    nazwa = dane.get("Name", "?")
    ent = dane.get("Entitlements", {})
    app_id = ent.get("application-identifier", "?")
    task_allow = ent.get("get-task-allow")
    urzadzenia = dane.get("ProvisionedDevices")

    print(f"  profil: {nazwa}")
    print(f"  app-identifier: {app_id}")
    print(f"  get-task-allow: {task_allow}")

    if app_id != f"{TEAM_ID}.{BUNDLE_ID}":
        bledy.append(f"profil dotyczy '{app_id}', a potrzebny '{TEAM_ID}.{BUNDLE_ID}'")
    if task_allow is not False:
        bledy.append(
            "profil ma get-task-allow=true, czyli jest DEWELOPERSKI. "
            "Do App Store potrzebny profil typu App Store."
        )
    if urzadzenia:
        bledy.append(
            f"profil ma liste {len(urzadzenia)} urzadzen - to znak profilu deweloperskiego, "
            "profil App Store nie ma takiej listy"
        )
    if nazwa != "TyfloCentrum App Store":
        ostrzezenia.append(
            f"nazwa profilu to '{nazwa}', a workflow oczekuje 'TyfloCentrum App Store' - "
            "albo zmien nazwe profilu, albo popraw PROVISIONING_PROFILE_SPECIFIER w workflow"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--katalog", required=True, help="katalog z plikami od Apple")
    ap.add_argument("--key-id", help="ASC_KEY_ID z App Store Connect")
    ap.add_argument("--issuer-id", help="ASC_ISSUER_ID z App Store Connect")
    ap.add_argument("--tylko-sprawdz", action="store_true", help="nie ustawiaj sekretow")
    a = ap.parse_args()

    kat = os.path.expanduser(a.katalog)
    print(f"katalog: {kat}\n")

    cer = znajdz(kat, ["*.cer", "distribution.cer"], "certyfikat .cer z kroku A")
    profil = znajdz(kat, ["*.mobileprovision"], "profil .mobileprovision z kroku B")
    p8 = znajdz(kat, ["AuthKey_*.p8", "*.p8"], "klucz API .p8 z kroku C")

    tmp = tempfile.mkdtemp(prefix="podpisywanie-")
    crt = None

    if cer:
        print("--- certyfikat ---")
        crt = sprawdz_certyfikat(cer, tmp)
    if profil:
        print("\n--- profil ---")
        sprawdz_profil(profil)
    if p8:
        print(f"\n--- klucz API ---\n  plik: {os.path.basename(p8)}")
        if not a.key_id:
            # Key ID siedzi w nazwie pliku: AuthKey_ABC123DEFG.p8
            baza = os.path.basename(p8)
            if baza.startswith("AuthKey_") and baza.endswith(".p8"):
                a.key_id = baza[len("AuthKey_"):-3]
                print(f"  Key ID odczytany z nazwy pliku: {a.key_id}")

    print()
    for o in ostrzezenia:
        print(f"OSTRZEZENIE: {o}")
    if bledy:
        print("\n=== BLEDY, nie ustawiam sekretow ===")
        for b in bledy:
            print(f"  - {b}")
        return 1

    print("=== wszystkie kontrole przeszly ===")

    if a.tylko_sprawdz:
        print("(--tylko-sprawdz: koncze bez ustawiania sekretow)")
        return 0

    if not a.key_id or not a.issuer_id:
        print("\nBRAK --key-id albo --issuer-id, nie moge ustawic sekretow ASC.", file=sys.stderr)
        return 1

    # .p12 z losowym haslem. -legacy, bo nowszy OpenSSL robi format,
    # ktorego keychain macOS nie zawsze czyta.
    haslo = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(24))
    p12 = os.path.join(tmp, "dist.p12")
    kod, out = uruchom([
        "openssl", "pkcs12", "-export", "-legacy",
        "-inkey", KLUCZ_PRYWATNY, "-in", crt or "",
        "-out", p12, "-name", "Apple Distribution",
        "-passout", f"pass:{haslo}",
    ])
    if kod != 0:
        print(f"nie udalo sie zlozyc .p12: {out.strip()[:300]}", file=sys.stderr)
        return 1
    print(f"zlozony .p12 ({os.path.getsize(p12)} B)")

    def b64(sciezka: str) -> str:
        with open(sciezka, "rb") as f:
            return base64.b64encode(f.read()).decode()

    sekrety = {
        "APPLE_DIST_CERT_P12_BASE64": b64(p12),
        "APPLE_DIST_CERT_PASSWORD": haslo,
        "APPLE_PROVISIONING_PROFILE_BASE64": b64(profil or ""),
        "APPLE_TEAM_ID": TEAM_ID,
        "ASC_KEY_ID": a.key_id,
        "ASC_ISSUER_ID": a.issuer_id,
        "ASC_API_KEY_P8_BASE64": b64(p8 or ""),
    }

    print("\n--- srodowisko 'release' ---")
    uruchom([
        "gh", "api", "-X", "PUT", f"repos/{REPO}/environments/release",
        "-F", "deployment_branch_policy[protected_branches]=false",
        "-F", "deployment_branch_policy[custom_branch_policies]=true",
    ])
    uruchom([
        "gh", "api", "-X", "POST", f"repos/{REPO}/environments/release/deployment-branch-policies",
        "-f", "name=master", "-f", "type=branch",
    ])

    print("--- sekrety ---")
    for nazwa, wartosc in sekrety.items():
        kod, out = uruchom(
            ["gh", "secret", "set", nazwa, "--env", "release", "--repo", REPO],
            wejscie=wartosc.encode(),
        )
        print(f"  {nazwa}: {'OK' if kod == 0 else 'BLAD ' + out.strip()[:120]}")

    print("\nGotowe. Odpal workflow:")
    print(f"  gh workflow run ios-testflight.yml -R {REPO} --ref master -f potwierdzam=tak")
    return 0


if __name__ == "__main__":
    sys.exit(main())
