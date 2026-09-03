#!/usr/bin/env python3
"""Test kontrastu kolorow przyciskow akcji wg WCAG.

PO CO. Zgloszenie od uzytkownikow: przyciski predkosci, znacznikow czasu i
ulubionych sa slabo widoczne przy zwiekszonym kontrascie. Pomiar na zrzucie
ekranu potwierdzil to liczbowo - systemowy szary przycisk .bordered mial
granice 1,21:1 wobec tla strony, przy progu WCAG 1.4.11 wynoszacym 3:1.

Autor projektu jest niewidomy i NIE ZWERYFIKUJE koloru wzrokiem, wiec kontrast
musi byc pilnowany LICZBA, a nie ogledem. Ten test czyta wartosci RGB WPROST
z Tyflocentrum/Views/StylPrzyciskuAkcji.swift, wiec podmiana koloru bez
sprawdzenia kontrastu wywali test, zamiast przejsc niezauwazona.

Progi (WCAG 2.2):
  1.4.3 Contrast (Minimum)        tekst zwykly            >= 4,5:1
  1.4.11 Non-text Contrast        granica kontrolki       >= 3:1

Uzycie:
  python3 tools/test_kontrast_przyciskow.py
  python3 tools/test_kontrast_przyciskow.py --kontrola-waznosci
"""
import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZRODLO = os.path.join(REPO, "Tyflocentrum/Views/StylPrzyciskuAkcji.swift")

PROG_TEKST = 4.5
PROG_KONTROLKA = 3.0

# Tlo ekranu w trybie jasnym. Zmierzone na realnym zrzucie (dominujacy kolor
# pikseli poza kontrolkami), nie zalozone.
TLO_JASNE = (255, 255, 255)

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


def luminancja(kolor):
    """Relatywna luminancja wg definicji WCAG."""
    def kanal(v):
        v = v / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = kolor[:3]
    return 0.2126 * kanal(r) + 0.7152 * kanal(g) + 0.0722 * kanal(b)


def kontrast(a, b):
    """Wspolczynnik kontrastu wg WCAG (od 1:1 do 21:1)."""
    l1, l2 = sorted([luminancja(a), luminancja(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def zmieszaj(kolor, tlo, alfa):
    """Kolor wynikowy po nalozeniu `kolor` z przezroczystoscia `alfa` na `tlo`.

    Potrzebne, bo SwiftUI `.opacity(0.12)` NIE zmienia progu WCAG - liczy sie
    kolor, ktory realnie widzi uzytkownik, czyli wynik mieszania z tlem.
    """
    return tuple(round(kolor[i] * alfa + tlo[i] * (1 - alfa)) for i in range(3))


def wczytaj_kolory():
    """Wyciagnij krotki RGB ze zrodla Swift."""
    with open(ZRODLO, encoding="utf-8") as f:
        tresc = f.read()
    kolory = {}
    for nazwa in ("wypelnienieRGB", "obramowanieRGB"):
        m = re.search(
            rf"{nazwa}\s*=\s*\(r:\s*(\d+),\s*g:\s*(\d+),\s*b:\s*(\d+)\)", tresc)
        if m:
            kolory[nazwa] = tuple(int(g) for g in m.groups())
    return kolory


def testy(kolory=None):
    kolory = kolory or wczytaj_kolory()
    sprawdz(f"kolory wczytane ze zrodla Swift ({kolory})", len(kolory) == 2)
    if len(kolory) != 2:
        return

    wypelnienie = kolory["wypelnienieRGB"]
    obramowanie = kolory["obramowanieRGB"]
    bialy = (255, 255, 255)

    print("--- 1. przycisk GLOWNY: bialy tekst na wypelnieniu (prog 4,5:1) ---")
    w = kontrast(bialy, wypelnienie)
    sprawdz(f"bialy tekst na {wypelnienie}: {w:.2f}:1", w >= PROG_TEKST)

    print("--- 2. przycisk GLOWNY: granica vs tlo ekranu (prog 3:1) ---")
    g = kontrast(wypelnienie, TLO_JASNE)
    sprawdz(f"wypelnienie vs biale tlo: {g:.2f}:1", g >= PROG_KONTROLKA)

    print("--- 3. przycisk DRUGORZEDNY: tekst na tle ekranu (prog 4,5:1) ---")
    t = kontrast(obramowanie, TLO_JASNE)
    sprawdz(f"tekst {obramowanie} na bialym: {t:.2f}:1", t >= PROG_TEKST)

    print("--- 4. przycisk DRUGORZEDNY: obramowanie vs tlo (prog 3:1) ---")
    o = kontrast(obramowanie, TLO_JASNE)
    sprawdz(f"obramowanie vs biale tlo: {o:.2f}:1", o >= PROG_KONTROLKA)

    print("--- 5. REGRESJA: nie wracamy do systemowego szarego ani niebieskiego ---")
    # Te dwie wartosci ZMIERZONO na zrzucie jako niewystarczajace. Test pilnuje,
    # zeby ktos ich nie przywrocil "bo tak jest systemowo".
    szary_systemowy = (233, 233, 235)
    niebieski_systemowy = (0, 136, 255)
    sprawdz(f"wypelnienie != systemowy szary {szary_systemowy} (mial 1,21:1)",
            wypelnienie != szary_systemowy)
    sprawdz(f"wypelnienie != systemowy niebieski {niebieski_systemowy} "
            f"(bialy tekst mial {kontrast(bialy, niebieski_systemowy):.2f}:1)",
            wypelnienie != niebieski_systemowy)

    print("--- 6. sanity-check samej miary kontrastu ---")
    # Liczba bez sanity-checku jest twierdzeniem, nie pomiarem: sprawdzamy, ze
    # funkcja daje znane wartosci skrajne.
    sprawdz(f"czarny na bialym = 21:1 (wyszlo {kontrast((0, 0, 0), bialy):.2f})",
            abs(kontrast((0, 0, 0), bialy) - 21.0) < 0.1)
    sprawdz(f"bialy na bialym = 1:1 (wyszlo {kontrast(bialy, bialy):.2f})",
            abs(kontrast(bialy, bialy) - 1.0) < 0.01)

    print("--- 7. PULAPKA POLPRZEZROCZYSTOSCI: samo tlo 12% NIE wystarcza ---")
    # Ekran glosowki mial Color.accentColor.opacity(0.12) jako CALE oznaczenie
    # kontrolki. Zmierzone: to daje 1,17:1, czyli kontrolka praktycznie znika.
    # Wniosek ogolny: przy polprzezroczystym wypelnieniu granice MUSI dawac
    # obramowanie, bo samo tlo nie przejdzie progu. Ten test pilnuje, zebysmy
    # nie "naprawili" tego z powrotem samym kolorem z alfa.
    mieszane = zmieszaj(wypelnienie, TLO_JASNE, 0.12)
    k_tla = kontrast(mieszane, TLO_JASNE)
    sprawdz(f"tlo 12% ({mieszane}) samo NIE spelnia 3:1 - dlatego jest obramowanie "
            f"({k_tla:.2f}:1)", k_tla < PROG_KONTROLKA)
    k_obramowania = kontrast(obramowanie, TLO_JASNE)
    sprawdz(f"ale obramowanie {obramowanie} spelnia 3:1 ({k_obramowania:.2f}:1)",
            k_obramowania >= PROG_KONTROLKA)


def kontrola_waznosci():
    """Podstaw kolory, ktore MUSZA obalic test."""
    global bledy, zrobione
    wyniki = []

    przypadki = [
        ("systemowy szary (zmierzone 1,21:1 - stan PRZED naprawa)",
         {"wypelnienieRGB": (233, 233, 235), "obramowanieRGB": (233, 233, 235)}),
        ("systemowy niebieski (bialy tekst 3,52:1 - za malo)",
         {"wypelnienieRGB": (0, 136, 255), "obramowanieRGB": (0, 136, 255)}),
        ("jasnozielony (typowy blad: 'ladny', ale nieczytelny)",
         {"wypelnienieRGB": (120, 220, 120), "obramowanieRGB": (120, 220, 120)}),
        ("bialy na bialym (skrajnosc)",
         {"wypelnienieRGB": (255, 255, 255), "obramowanieRGB": (255, 255, 255)}),
    ]

    print("=== WERSJA Z KODU (musi PRZEJSC) ===")
    bledy, zrobione = [], 0
    testy()
    poprawna = len(bledy)
    print(f"  -> bledow: {poprawna}")

    for opis, kolory in przypadki:
        bledy, zrobione = [], 0
        print(f"\n=== psuje: {opis} ===")
        testy(kolory)
        wyniki.append((opis, len(bledy)))

    print("\n=== PODSUMOWANIE KONTROLI WAZNOSCI ===")
    print(f"  wersja z kodu: bledow={poprawna}")
    for opis, n in wyniki:
        print(f"  {opis[:52]:54s} bledow={n:2d}  "
              f"{'wykryte' if n else 'NIE WYKRYTE - ATRAPA'}")
    slabe = [o for o, n in wyniki if n == 0]
    if poprawna != 0:
        print("\nKONTROLA PADLA: wersja z kodu NIE przechodzi testu")
        return 1
    if slabe:
        print(f"\nKONTROLA PADLA: przeszlo niezauwazone: {slabe}")
        return 1
    print("\nKONTROLA WAZNOSCI OK: kazdy zly kolor zostal wykryty")
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
