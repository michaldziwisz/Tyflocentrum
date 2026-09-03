#!/usr/bin/env python3
"""Bramka: projekt musi byc podpisywany NASZYM kontem Apple.

PO CO. Repo jest forkiem Nuno69/Tyflocentrum, a DEVELOPMENT_TEAM przyszlo
z PIERWSZEGO commita pierwotnego maintainera (0bd203d, 2022-10-02). To bylo
JEGO konto Apple. Przejelismy projekt i wydajemy pod kontem Michala, wiec ta
wartosc musi byc nasza - inaczej podpisywanie i wysylka do App Store Connect
nie przejda, a w skrajnym przypadku probowalibysmy wydac aplikacje "w imieniu"
kogos, kto sie nia nie zajmuje.

DLACZEGO BRAMKA, A NIE JEDNORAZOWA PODMIANA. Kazdy przyszly merge z upstreamu
moze przywrocic stara wartosc, bo dotyka tego samego pliku project.pbxproj.
Taki powrot jest CICHY: kod sie kompiluje, testy przechodza, a build po prostu
nie da sie podpisac naszym certyfikatem. Ta bramka zamienia cicha awarie
w jawny blad na CI.

Uzycie:
  python3 tools/test_konto_apple.py
  python3 tools/test_konto_apple.py --kontrola-waznosci
"""
import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJEKT = os.path.join(REPO, "Tyflocentrum.xcodeproj/project.pbxproj")

# Nasze konto (Michal Dziwisz, michal@dziwisz.net). To samo, z ktorego wydajemy
# Sterigo - potwierdzone przy tamtym setupie: Membership Individual, Account Holder.
NASZ_TEAM_ID = "X2FN885LQU"

# Konto pierwotnego maintainera. Trzymamy je tu JAWNIE, zeby bramka umiala
# powiedziec "wrocilo cudze konto" zamiast tylko "cos sie nie zgadza".
TEAM_ID_MAINTAINERA = "A86C2NBH8N"

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


def wczytaj(tresc=None):
    if tresc is not None:
        return tresc
    with open(PROJEKT, encoding="utf-8") as f:
        return f.read()


def testy(tresc=None):
    t = wczytaj(tresc)

    print("--- 1. DEVELOPMENT_TEAM wskazuje NASZE konto ---")
    znalezione = set(re.findall(r"DEVELOPMENT_TEAM = ([A-Z0-9]+);", t))
    sprawdz(f"zestaw team ID w projekcie: {sorted(znalezione) or 'BRAK'}",
            znalezione == {NASZ_TEAM_ID})

    print("--- 2. konto maintainera NIE wrocilo (np. przez merge z upstreamu) ---")
    sprawdz(f"brak {TEAM_ID_MAINTAINERA} w pliku projektu",
            TEAM_ID_MAINTAINERA not in t)

    print("--- 3. kazdy target aplikacji MA ustawiony team ---")
    # Puste DEVELOPMENT_TEAM = "" jest gorsze niz zle: Xcode wybiera wtedy
    # dowolny dostepny zespol, wiec build "dziala" u jednej osoby i pada u drugiej.
    sprawdz("brak pustych DEVELOPMENT_TEAM",
            'DEVELOPMENT_TEAM = "";' not in t and "DEVELOPMENT_TEAM = ;" not in t)
    ile = len(re.findall(r"DEVELOPMENT_TEAM = ", t))
    sprawdz(f"liczba wpisow DEVELOPMENT_TEAM = {ile} (>=2: Debug i Release)",
            ile >= 2)

    print("--- 4. bundle ID nalezy do NASZEJ przestrzeni nazw ---")
    bundle = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", t))
    glowne = {b for b in bundle if not b.endswith(("Tests", "UITests"))}
    sprawdz(f"bundle ID aplikacji: {sorted(glowne)}",
            glowne == {"net.tyflocentrum.app"})


def kontrola_waznosci():
    """Podstaw tresci, ktore MUSZA obalic bramke."""
    global bledy, zrobione
    wyniki = []
    oryginal = wczytaj()

    przypadki = [
        ("powrot konta maintainera (typowy skutek merge z upstreamu)",
         oryginal.replace(f"DEVELOPMENT_TEAM = {NASZ_TEAM_ID};",
                          f"DEVELOPMENT_TEAM = {TEAM_ID_MAINTAINERA};")),
        ("PUSTY team (Xcode wybierze dowolny - build dziala u jednego, pada u drugiego)",
         oryginal.replace(f"DEVELOPMENT_TEAM = {NASZ_TEAM_ID};",
                          'DEVELOPMENT_TEAM = "";')),
        ("obce, losowe konto",
         oryginal.replace(f"DEVELOPMENT_TEAM = {NASZ_TEAM_ID};",
                          "DEVELOPMENT_TEAM = ZZ99XX88YY;")),
        ("podmieniony bundle ID (np. przez cudzy szablon)",
         oryginal.replace("PRODUCT_BUNDLE_IDENTIFIER = net.tyflocentrum.app;",
                          "PRODUCT_BUNDLE_IDENTIFIER = com.example.app;")),
    ]

    print("=== WERSJA Z REPO (musi PRZEJSC) ===")
    bledy, zrobione = [], 0
    testy()
    poprawna = len(bledy)
    print(f"  -> bledow: {poprawna}")

    for opis, tresc in przypadki:
        bledy, zrobione = [], 0
        print(f"\n=== psuje: {opis} ===")
        testy(tresc)
        wyniki.append((opis, len(bledy)))

    print("\n=== PODSUMOWANIE KONTROLI WAZNOSCI ===")
    print(f"  wersja z repo: bledow={poprawna}")
    for opis, n in wyniki:
        print(f"  {opis[:58]:60s} bledow={n:2d}  "
              f"{'wykryte' if n else 'NIE WYKRYTE - ATRAPA'}")
    slabe = [o for o, n in wyniki if n == 0]
    if poprawna != 0:
        print("\nKONTROLA PADLA: wersja z repo NIE przechodzi bramki")
        return 1
    if slabe:
        print(f"\nKONTROLA PADLA: przeszlo niezauwazone: {slabe}")
        return 1
    print("\nKONTROLA WAZNOSCI OK: kazde podmienione konto zostalo wykryte")
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
        print("BRAMKA PADLA")
        return 1
    print("WSZYSTKO ZIELONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
