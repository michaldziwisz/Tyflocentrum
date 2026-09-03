#!/usr/bin/env python3
"""Znajdz UDID symulatora iOS po DOKLADNEJ nazwie.

PO COMO DOKLADNEJ: dopasowanie po prefiksie trafia w zle urzadzenie -
"iPad Pro 11-inch (M5)" pasuje do zapytania "iPad Pro 1...", a zrzuty
z 11-calowego iPada NIE spelniaja wymogu Apple dla klasy 13".

Uzycie: udid_symulatora.py "iPad Pro 13-inch (M5)"
Kod 0 = wypisany UDID, kod 1 = nie ma takiego symulatora.
"""
import json
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        print("Uzycie: udid_symulatora.py \"<dokladna nazwa>\"", file=sys.stderr)
        return 2
    szukana = sys.argv[1].strip()

    wynik = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True, text=True,
    )
    if wynik.returncode != 0:
        print("simctl zwrocil blad:", wynik.stderr[:400], file=sys.stderr)
        return 2

    urzadzenia = json.loads(wynik.stdout).get("devices", {})
    dostepne = []
    for runtime, lista in urzadzenia.items():
        if "iOS" not in runtime:
            continue
        for u in lista:
            if not u.get("isAvailable"):
                continue
            dostepne.append(u["name"])
            if u["name"] == szukana:
                print(u["udid"])
                return 0

    print(f"Brak symulatora o nazwie: {szukana!r}", file=sys.stderr)
    print("Dostepne (iOS):", file=sys.stderr)
    for n in sorted(set(dostepne)):
        print("  -", n, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
