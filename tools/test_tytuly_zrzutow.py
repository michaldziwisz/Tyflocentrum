#!/usr/bin/env python3
"""Test kolejnosci podmiany tytulow do zrzutow (logika daneDoZrzutu).

PO CO OSOBNY TEST W PYTHONIE: Xcode jest tylko na runnerze, a ta funkcja ma
JEDNA subtelnosc, ktora psuje sie cicho - kolejnosc podmiany. Klucze sa
przedrostkami siebie ("Test podcast" jest przedrostkiem "Test podcast 2"), wiec
podmiana od najkrotszego zostawia ogonek: "Test podcast 2" -> "<nowy tytul> 2".
Efekt nie wywala testu ani builda, tylko brzydzi na zrzucie wyslanym do Apple.

Test odtwarza TE SAMA regule (sortowanie po dlugosci klucza malejaco) i sprawdza,
ze wynik nie zawiera resztek. Kontrola waznosci uruchamia wersje BEZ sortowania
i wymaga, zeby test ja OBALIL - inaczej nie mierzy niczego.

Zrodlo prawdy: Tyflocentrum/TyflocentrumApp.swift, slownik tytulyDoZrzutow.
Gdy tam dopiszesz pozycje, dopisz ja tez tutaj (test SPRAWDZA zgodnosc obu list).

Uzycie:
  python3 tools/test_tytuly_zrzutow.py
  python3 tools/test_tytuly_zrzutow.py --kontrola-waznosci
"""
import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZRODLO = os.path.join(REPO, "Tyflocentrum/TyflocentrumApp.swift")

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


def wczytaj_slownik_ze_swifta():
    """Wyciagnij pary klucz->wartosc ze slownika tytulyDoZrzutow w kodzie Swift."""
    with open(ZRODLO, encoding="utf-8") as f:
        tresc = f.read()
    poczatek = tresc.find("tytulyDoZrzutow: [String: String] = [")
    if poczatek == -1:
        return None
    # Koniec bloku to nawias zamykajacy NA POCZATKU LINII (z wcieciem tabem),
    # nie pierwszy napotkany "]" - wartosci zawieraja nawiasy i cudzyslowy,
    # a naiwne szukanie "]" ucinalo blok na zerowej pozycji.
    dopasowanie = re.search(r"\n\t\]", tresc[poczatek:])
    koniec = poczatek + (dopasowanie.start() if dopasowanie else len(tresc))
    blok = tresc[poczatek:koniec]
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', blok))


def podmien(tekst, slownik, sortuj=True):
    """Odtworzenie reguly z daneDoZrzutu."""
    pary = slownik.items()
    if sortuj:
        pary = sorted(pary, key=lambda kv: -len(kv[0]))
    for stary, nowy in pary:
        tekst = tekst.replace(stary, nowy)
    return tekst


def testy(sortuj=True):
    slownik = wczytaj_slownik_ze_swifta()
    if slownik is None:
        sprawdz("slownik tytulyDoZrzutow znaleziony w kodzie Swift", False)
        return
    sprawdz(f"slownik wczytany z kodu Swift ({len(slownik)} pozycji)", bool(slownik))

    print("--- 1. kazdy tytul testowy zostaje podmieniony ---")
    for klucz in sorted(slownik, key=len, reverse=True):
        wynik = podmien(klucz, slownik, sortuj)
        sprawdz(f"{klucz!r} -> {wynik!r}", wynik == slownik[klucz])

    print("--- 2. po podmianie NIE ZOSTAJE slowo 'Test' ani ogonek liczby ---")
    # Pelna lista w jednym tekscie, tak jak w prawdziwej odpowiedzi JSON.
    wejscie = " | ".join(sorted(slownik, key=len, reverse=True))
    wynik = podmien(wejscie, slownik, sortuj)
    sprawdz(f"brak slowa 'Test' w wyniku (wynik: {wynik[:80]}...)",
            "Test" not in wynik)
    # Ogonek to nowy tytul, po ktorym zostala samotna cyfra z klucza.
    ogonki = re.findall(r"[a-ząćęłńóśźż]\s+\d\b", wynik)
    sprawdz(f"brak osieroconych cyfr po podmianie (znalezione: {ogonki})",
            not ogonki)

    print("--- 3. realistyczny JSON atrapy ---")
    json_atrapy = (
        '[{"id":1,"title":{"rendered":"Test podcast"},"excerpt":{"rendered":"Excerpt"}},'
        '{"id":3,"title":{"rendered":"Test podcast 2"},"excerpt":{"rendered":"Excerpt"}}]'
    )
    wynik = podmien(json_atrapy, slownik, sortuj)
    sprawdz("tytul 'Test podcast' podmieniony w JSON",
            slownik["Test podcast"] in wynik)
    sprawdz("tytul 'Test podcast 2' podmieniony POPRAWNIE (bez ogonka)",
            slownik["Test podcast 2"] in wynik
            and f'{slownik["Test podcast"]} 2' not in wynik)
    sprawdz("JSON pozostal poprawny skladniowo",
            wynik.count("{") == json_atrapy.count("{")
            and wynik.count("}") == json_atrapy.count("}"))

    print("--- 4. tytuly wygladaja jak tresc produkcyjna, nie testowa ---")
    for klucz, wartosc in sorted(slownik.items()):
        podejrzane = [w for w in ("test", "lorem", "ipsum", "placeholder", "foo", "bar")
                      if w in wartosc.lower()]
        sprawdz(f"{wartosc!r} bez slow-atrap {podejrzane if podejrzane else ''}",
                not podejrzane)


def kontrola_waznosci():
    """Bez sortowania po dlugosci test MUSI padnac. Inaczej jest atrapa."""
    global bledy, zrobione

    print("=== WERSJA POPRAWNA (sortowanie po dlugosci klucza) ===")
    bledy, zrobione = [], 0
    testy(sortuj=True)
    poprawna = len(bledy)
    print(f"  -> bledow: {poprawna}")

    print()
    print("=== WERSJA USZKODZONA (bez sortowania - kolejnosc slownika) ===")
    bledy, zrobione = [], 0
    testy(sortuj=False)
    uszkodzona = len(bledy)
    print(f"  -> bledow: {uszkodzona}")

    print()
    print("=== PODSUMOWANIE KONTROLI WAZNOSCI ===")
    print(f"  wersja poprawna:   bledow={poprawna}")
    print(f"  wersja uszkodzona: bledow={uszkodzona}")
    if poprawna != 0:
        print("\nKONTROLA PADLA: wersja POPRAWNA nie przechodzi testu")
        return 1
    if uszkodzona == 0:
        print("\nKONTROLA PADLA: uszkodzenie kolejnosci przeszlo NIEZAUWAZONE "
              "- test jest atrapa")
        return 1
    print("\nKONTROLA WAZNOSCI OK: test przechodzi dla poprawnej wersji "
          "i OBALA wersje bez sortowania")
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
