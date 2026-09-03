#!/usr/bin/env python3
"""Test manifestu prywatnosci i deklaracji eksportowej.

PO CO. Apple: "Starting May 1, 2024, apps that don't describe their use of
required reason API in their privacy manifest file aren't accepted by App Store
Connect". To jest warunek WYSYLKI, nie polish - dlatego ma test, a nie notatke
w dokumencie (CODE_REVIEW_APPSTORE.md nazywal manifest "opcjonalnym" i przez
pol roku nikt tego nie zweryfikowal).

NAJWAZNIEJSZA ASERCJA: manifest musi byc W ZASOBACH TARGETU, nie tylko na dysku.
Plik lezacy obok projektu, ale niepodpiety do "Copy Bundle Resources", NIE trafia
do builda - czyli App Store go nie zobaczy, a my mielibysmy falszywe poczucie
zalatwionej sprawy.

DRUGA: kategorie w manifescie musza odpowiadac TEMU, CO KOD REALNIE ROBI.
Manifest deklarujacy za malo = odrzucenie wysylki; deklarujacy cokolwiek na
zapas = oswiadczenie niezgodne z prawda wobec Apple. Dlatego test SKANUJE kod
i porownuje wynik z manifestem w OBIE strony.

Uruchomienie:        python3 tools/test_manifest_prywatnosci.py
Kontrola waznosci:   python3 tools/test_manifest_prywatnosci.py --kontrola-waznosci
"""
import argparse
import os
import plistlib
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "Tyflocentrum/PrivacyInfo.xcprivacy")
INFO_PLIST = os.path.join(REPO, "Tyflocentrum/Info.plist")
PBXPROJ = os.path.join(REPO, "Tyflocentrum.xcodeproj/project.pbxproj")
ZRODLA = os.path.join(REPO, "Tyflocentrum")

# Wzorce API wymagajacych deklaracji -> kategoria manifestu.
# Tylko te, ktore realnie moga wystapic w tej aplikacji; lista Apple jest dluzsza.
WZORCE = {
    "NSPrivacyAccessedAPICategoryUserDefaults": [r"\bUserDefaults\b"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": [
        r"\.fileSizeKey", r"\.creationDateKey", r"\.contentModificationDateKey",
    ],
    "NSPrivacyAccessedAPICategoryDiskSpace": [
        r"volumeAvailableCapacity", r"systemFreeSize",
    ],
    "NSPrivacyAccessedAPICategorySystemBootTime": [r"mach_absolute_time"],
}

bledy = []
zrobione = 0


def sprawdz(opis, warunek):
    global zrobione
    zrobione += 1
    if warunek:
        print(f"  OK   {opis}")
    else:
        print(f"  BLAD {opis}")
        bledy.append(opis)


def skanuj_kod(katalog):
    """Ktore kategorie required-reason API wystepuja w kodzie produkcyjnym."""
    znalezione = {}
    for korzen, _kat, pliki in os.walk(katalog):
        for nazwa in pliki:
            if not nazwa.endswith(".swift"):
                continue
            sciezka = os.path.join(korzen, nazwa)
            with open(sciezka, encoding="utf-8", errors="replace") as f:
                tresc = f.read()
            # Komentarze potrafia zawierac nazwy API (np. w wyjasnieniu, czemu
            # czegos NIE uzywamy) - liczymy tylko kod.
            kod = "\n".join(
                l for l in tresc.splitlines()
                if not l.lstrip().startswith("//")
            )
            for kategoria, wzorce in WZORCE.items():
                if any(re.search(w, kod) for w in wzorce):
                    znalezione.setdefault(kategoria, set()).add(
                        os.path.relpath(sciezka, REPO))
    return znalezione


def testy(manifest=MANIFEST, info_plist=INFO_PLIST, pbxproj=PBXPROJ, zrodla=ZRODLA):
    print("--- 1. manifest istnieje i jest poprawnym plistem ---")
    if not os.path.exists(manifest):
        sprawdz("PrivacyInfo.xcprivacy istnieje", False)
        return
    sprawdz("PrivacyInfo.xcprivacy istnieje", True)
    try:
        with open(manifest, "rb") as f:
            m = plistlib.load(f)
        sprawdz("manifest parsuje sie jako plist", True)
    except Exception as e:
        sprawdz(f"manifest parsuje sie jako plist ({e})", False)
        return

    print("--- 2. manifest jest W ZASOBACH TARGETU (inaczej nie trafi do builda) ---")
    with open(pbxproj, encoding="utf-8", errors="replace") as f:
        proj = f.read()
    sprawdz("PrivacyInfo.xcprivacy ma PBXFileReference",
            "PrivacyInfo.xcprivacy */ = {isa = PBXFileReference" in proj)
    sprawdz("PrivacyInfo.xcprivacy jest w fazie Resources",
            "PrivacyInfo.xcprivacy in Resources */," in proj)

    print("--- 3. deklaracja sledzenia ---")
    sprawdz("NSPrivacyTracking = false (nie sledzimy)",
            m.get("NSPrivacyTracking") is False)
    sprawdz("NSPrivacyTrackingDomains puste",
            m.get("NSPrivacyTrackingDomains") == [])

    print("--- 4. zgodnosc manifestu z KODEM (w obie strony) ---")
    w_kodzie = skanuj_kod(zrodla)
    w_manifescie = {
        t.get("NSPrivacyAccessedAPIType")
        for t in m.get("NSPrivacyAccessedAPITypes", [])
    }
    for kat, pliki in sorted(w_kodzie.items()):
        skrot = ", ".join(sorted(os.path.basename(p) for p in pliki)[:3])
        sprawdz(f"{kat}: uzywane w kodzie ({skrot}) i ZADEKLAROWANE",
                kat in w_manifescie)
    nadmiarowe = w_manifescie - set(w_kodzie)
    sprawdz(f"brak deklaracji 'na zapas' (nadmiarowe: {sorted(nadmiarowe)})",
            not nadmiarowe)

    print("--- 5. kazda kategoria ma NIEPUSTA liste powodow ---")
    for t in m.get("NSPrivacyAccessedAPITypes", []):
        kat = t.get("NSPrivacyAccessedAPIType", "?")
        powody = t.get("NSPrivacyAccessedAPITypeReasons") or []
        # Kod przyczyny ma postac 4 znaki HEX, kropka, cyfra (np. CA92.1).
        poprawne = all(re.fullmatch(r"[0-9A-F]{4}\.\d", str(p)) for p in powody)
        sprawdz(f"{kat}: powody {powody} niepuste i w formacie Apple",
                bool(powody) and poprawne)

    print("--- 6. deklaracja eksportowa w Info.plist ---")
    try:
        with open(info_plist, "rb") as f:
            ip = plistlib.load(f)
        sprawdz("Info.plist parsuje sie", True)
    except Exception as e:
        sprawdz(f"Info.plist parsuje sie ({e})", False)
        return
    sprawdz("ITSAppUsesNonExemptEncryption obecne (zdejmuje pytanie przy kazdej wysylce)",
            "ITSAppUsesNonExemptEncryption" in ip)
    sprawdz("ITSAppUsesNonExemptEncryption = false (tylko HTTPS/TLS systemu)",
            ip.get("ITSAppUsesNonExemptEncryption") is False)
    sprawdz("NSMicrophoneUsageDescription nadal obecne (glosowki)",
            bool(ip.get("NSMicrophoneUsageDescription")))


def kontrola_waznosci():
    """Psuje po jednej rzeczy naraz i sprawdza, ze test to wykrywa."""
    import shutil
    import tempfile

    global bledy, zrobione
    wyniki = []

    with open(MANIFEST, "rb") as f:
        oryginal = plistlib.load(f)
    with open(INFO_PLIST, "rb") as f:
        oryginal_info = plistlib.load(f)

    def zapisz(katalog, manifest_dane, info_dane, proj_tresc):
        os.makedirs(os.path.join(katalog, "Tyflocentrum"), exist_ok=True)
        os.makedirs(os.path.join(katalog, "Tyflocentrum.xcodeproj"), exist_ok=True)
        mp = os.path.join(katalog, "Tyflocentrum/PrivacyInfo.xcprivacy")
        with open(mp, "wb") as f:
            plistlib.dump(manifest_dane, f)
        ip = os.path.join(katalog, "Tyflocentrum/Info.plist")
        with open(ip, "wb") as f:
            plistlib.dump(info_dane, f)
        pp = os.path.join(katalog, "Tyflocentrum.xcodeproj/project.pbxproj")
        with open(pp, "w", encoding="utf-8") as f:
            f.write(proj_tresc)
        return mp, ip, pp

    with open(PBXPROJ, encoding="utf-8", errors="replace") as f:
        proj_ok = f.read()
    proj_bez = proj_ok.replace("PrivacyInfo.xcprivacy in Resources */,", "")

    import copy
    przypadki = []

    bez_userdefaults = copy.deepcopy(oryginal)
    bez_userdefaults["NSPrivacyAccessedAPITypes"] = [
        t for t in bez_userdefaults["NSPrivacyAccessedAPITypes"]
        if t["NSPrivacyAccessedAPIType"] != "NSPrivacyAccessedAPICategoryUserDefaults"
    ]
    przypadki.append(("brakuje kategorii uzywanej w kodzie",
                      bez_userdefaults, oryginal_info, proj_ok))

    nadmiar = copy.deepcopy(oryginal)
    nadmiar["NSPrivacyAccessedAPITypes"].append({
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace",
        "NSPrivacyAccessedAPITypeReasons": ["E174.1"],
    })
    przypadki.append(("deklaracja 'na zapas' (kategoria nieuzywana)",
                      nadmiar, oryginal_info, proj_ok))

    puste = copy.deepcopy(oryginal)
    puste["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = []
    przypadki.append(("pusta lista powodow", puste, oryginal_info, proj_ok))

    zly_kod = copy.deepcopy(oryginal)
    zly_kod["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = ["bo tak"]
    przypadki.append(("powod w zlym formacie", zly_kod, oryginal_info, proj_ok))

    sledzenie = copy.deepcopy(oryginal)
    sledzenie["NSPrivacyTracking"] = True
    przypadki.append(("NSPrivacyTracking = true", sledzenie, oryginal_info, proj_ok))

    bez_eksportu = copy.deepcopy(oryginal_info)
    bez_eksportu.pop("ITSAppUsesNonExemptEncryption", None)
    przypadki.append(("brak deklaracji eksportowej", oryginal, bez_eksportu, proj_ok))

    przypadki.append(("manifest NIE podpiety do zasobow targetu",
                      oryginal, oryginal_info, proj_bez))

    for opis, man, info, proj in przypadki:
        katalog = tempfile.mkdtemp()
        try:
            mp, ip, pp = zapisz(katalog, man, info, proj)
            bledy, zrobione = [], 0
            print(f"\n=== psuje: {opis} ===")
            testy(manifest=mp, info_plist=ip, pbxproj=pp, zrodla=ZRODLA)
            wyniki.append((opis, len(bledy)))
        finally:
            shutil.rmtree(katalog, ignore_errors=True)

    print("\n=== PODSUMOWANIE KONTROLI WAZNOSCI ===")
    slabe = [o for o, n in wyniki if n == 0]
    for opis, n in wyniki:
        print(f"  {opis:46s} bledow={n:2d}  "
              f"{'wykryte' if n else 'NIE WYKRYTE - ATRAPA'}")
    if slabe:
        print(f"\nKONTROLA PADLA: przeszlo niezauwazone: {slabe}")
        return 1
    print("\nKONTROLA WAZNOSCI OK: kazde uszkodzenie zostalo wykryte")
    return 0


def main():
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("--kontrola-waznosci", action="store_true")
    args = p.parse_args()

    if args.kontrola_waznosci:
        return kontrola_waznosci()

    testy()
    print()
    print(f"asercje: {zrobione}, bledy: {len(bledy)}")
    if bledy:
        print("TEST PADL")
        return 1
    print("WSZYSTKO ZIELONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
