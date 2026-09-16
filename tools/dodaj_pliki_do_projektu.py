#!/usr/bin/env python3
"""Dopisuje pliki zrodlowe Swift do project.pbxproj (format klasyczny, objectVersion 56).

PO CO SKRYPT, A NIE RECZNA EDYCJA. Projekt NIE uzywa synchronizowanych grup
(`PBXFileSystemSynchronizedRootGroup` nie wystepuje w pliku ani razu), wiec kazdy
nowy plik .swift trzeba wpisac w CZTERECH miejscach: PBXBuildFile,
PBXFileReference, `children` grupy oraz `files` fazy Sources. Pominiecie
ostatniego jest najgrozniejsze, bo projekt otwiera sie bez bledu, plik jest
widoczny w Xcode, a mimo to NIE trafia do kompilacji - usterka wychodzi dopiero
jako "cannot find ... in scope" na runnerze macOS, kilkanascie minut pozniej.
Reczne wklejanie czterech wpisow z wymyslonymi identyfikatorami to takze najlatwiejszy
sposob, zeby uszkodzic caly projekt literowka.

Skrypt jest IDEMPOTENTNY: plik juz obecny w projekcie zostaje pominiety, wiec
powtorne uruchomienie nie tworzy duplikatow (duplikat w fazie Sources = blad
"duplicate symbol" przy linkowaniu).

Identyfikatory sa DETERMINISTYCZNE (skrot sciezki), nie losowe - dzieki temu
powtorne wygenerowanie daje ten sam wynik i diff w gicie jest czytelny.

Uzycie:
    python3 tools/dodaj_pliki_do_projektu.py --pokaz     # diagnoza, NIC nie zapisuje
    python3 tools/dodaj_pliki_do_projektu.py --zapisz    # dopiero to modyfikuje plik
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path

KATALOG_REPO = Path(__file__).resolve().parent.parent
PBXPROJ = KATALOG_REPO / "Tyflocentrum.xcodeproj" / "project.pbxproj"

# Identyfikatory odczytane z project.pbxproj (nie zgadywane).
GRUPA_GLOWNA = "BEEA97B728E9D4BB0073E5AB"      # grupa Tyflocentrum
GRUPA_VIEWS = "BEA9ECD129203FD700718254"        # grupa Views
GRUPA_TESTY = "332BAE81609B20E1E52D9A53"        # grupa TyflocentrumTests
FAZA_APLIKACJA = "BEEA97B128E9D4BA0073E5AB"     # Sources targetu Tyflocentrum
FAZA_TESTY = "8ECB299EE7AD56B928399C9E"         # Sources targetu TyflocentrumTests

# Pliki do wpiecia: sciezka wzgledem repo -> (grupa, faza Sources).
PLIKI = [
    ("Tyflocentrum/StrategiaOdswiezania.swift", GRUPA_GLOWNA, FAZA_APLIKACJA),
    ("Tyflocentrum/ScalanieNowosci.swift", GRUPA_GLOWNA, FAZA_APLIKACJA),
    ("Tyflocentrum/Views/ZakladkaAplikacji.swift", GRUPA_VIEWS, FAZA_APLIKACJA),
    ("TyflocentrumTests/StrategiaOdswiezaniaTests.swift", GRUPA_TESTY, FAZA_TESTY),
]


def identyfikator(tekst: str, sufiks: str) -> str:
    """24-znakowy identyfikator w formacie Xcode, deterministyczny dla danej sciezki."""
    skrot = hashlib.sha1(f"{tekst}|{sufiks}".encode()).hexdigest().upper()
    return skrot[:24]


def wstaw_po_naglowku(tresc: str, sekcja: str, linia: str) -> str:
    """Wstawia linie zaraz po naglowku sekcji '/* Begin <sekcja> section */'."""
    znacznik = f"/* Begin {sekcja} section */"
    pozycja = tresc.index(znacznik) + len(znacznik)
    return tresc[:pozycja] + "\n" + linia + tresc[pozycja:]


def wstaw_do_listy(tresc: str, identyfikator_obiektu: str, linia: str) -> str:
    """Dopisuje wpis na koniec listy 'children'/'files' wskazanego obiektu."""
    # Szukamy bloku obiektu, potem PIERWSZEJ listy w nawiasach po 'children ='
    # albo 'files =' - obie konczy ');' w tej samej klamrze.
    wzorzec = re.compile(
        r"(\t\t" + re.escape(identyfikator_obiektu) + r" /\* [^*]* \*/ = \{.*?"
        r"(?:children|files) = \(\n)(.*?)(\t\t\t\);)",
        re.DOTALL,
    )
    dopasowanie = wzorzec.search(tresc)
    if not dopasowanie:
        raise SystemExit(f"BLAD: nie znalazlem listy dla obiektu {identyfikator_obiektu}")
    poczatek, wnetrze, koniec = dopasowanie.groups()
    return tresc.replace(
        dopasowanie.group(0),
        poczatek + wnetrze + linia + "\n" + koniec,
        1,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    grupa = parser.add_mutually_exclusive_group(required=True)
    grupa.add_argument("--pokaz", action="store_true", help="tylko diagnoza, bez zapisu")
    grupa.add_argument("--zapisz", action="store_true", help="zapisz zmiany w project.pbxproj")
    args = parser.parse_args()

    if not PBXPROJ.exists():
        raise SystemExit(f"BLAD: brak {PBXPROJ}")

    tresc = PBXPROJ.read_text(encoding="utf-8")
    oryginal = tresc
    dodane: list[str] = []
    pominiete: list[str] = []
    brakujace: list[str] = []

    for sciezka_rel, grupa_id, faza_id in PLIKI:
        sciezka = KATALOG_REPO / sciezka_rel
        nazwa = sciezka.name

        if not sciezka.exists():
            brakujace.append(sciezka_rel)
            continue

        # Idempotencja: sprawdzamy obecnosc W FAZIE SOURCES, nie samej nazwy w pliku.
        # Nazwa moze wystepowac jako komentarz przy innym obiekcie, a rozstrzyga to,
        # czy plik jest KOMPILOWANY.
        if re.search(re.escape(nazwa) + r" in Sources \*/", tresc):
            pominiete.append(sciezka_rel)
            continue

        ref_id = identyfikator(sciezka_rel, "ref")
        build_id = identyfikator(sciezka_rel, "build")

        tresc = wstaw_po_naglowku(
            tresc,
            "PBXBuildFile",
            f"\t\t{build_id} /* {nazwa} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {nazwa} */; }};",
        )
        tresc = wstaw_po_naglowku(
            tresc,
            "PBXFileReference",
            f"\t\t{ref_id} /* {nazwa} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {nazwa}; sourceTree = \"<group>\"; }};",
        )
        tresc = wstaw_do_listy(tresc, grupa_id, f"\t\t\t\t{ref_id} /* {nazwa} */,")
        tresc = wstaw_do_listy(tresc, faza_id, f"\t\t\t\t{build_id} /* {nazwa} in Sources */,")
        dodane.append(sciezka_rel)

    for sciezka in brakujace:
        print(f"  BRAK PLIKU NA DYSKU: {sciezka}")
    for sciezka in pominiete:
        print(f"  juz w projekcie:     {sciezka}")
    for sciezka in dodane:
        print(f"  DOPISANE:            {sciezka}")

    if brakujace:
        raise SystemExit("BLAD: nie wpisuje do projektu plikow, ktorych nie ma na dysku")

    if not dodane:
        print("Nic do zrobienia - wszystkie pliki sa juz w projekcie.")
        return 0

    if args.pokaz:
        print("\nTryb --pokaz: NIC nie zapisano. Uruchom z --zapisz.")
        return 0

    kopia = PBXPROJ.with_suffix(".pbxproj.kopia")
    shutil.copy2(PBXPROJ, kopia)
    PBXPROJ.write_text(tresc, encoding="utf-8")
    print(f"\nZapisano. Kopia poprzedniej wersji: {kopia}")
    print(f"Przyrost: {len(tresc) - len(oryginal)} znakow")
    return 0


if __name__ == "__main__":
    sys.exit(main())
