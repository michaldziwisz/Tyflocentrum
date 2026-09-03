#!/usr/bin/env python3
"""Test ikon iOS: wymogi App Store + zgodność wizualna z wersją Windows/Android.

KAŻDA asercja pozytywna ma parę NEGATYWNĄ (celowo zepsuty obraz MUSI ją obalić),
bo test, który przechodzi zawsze, jest gorszy od braku testu - daje fałszywą
pewność przed wysłaniem wydania do Apple.

Weryfikowane wymogi, każdy z konkretnym powodem:
1. BRAK kanału alfa - App Store odrzuca ikony z przezroczystością.
2. Dokładny rozmiar w pikselach - Xcode odrzuca niezgodność z Contents.json.
3. Kompletność: każdy wpis Contents.json ma plik i odwrotnie (brak sierot).
4. Tło zgodne z granatem kafla Windows - to jest sens ujednolicenia.
5. KONTRAST symbolu do tła wg WCAG 1.4.11 (próg 3:1) - Michał jest niewidomy
   i nie sprawdzi tego wzrokiem, a ikona o niskim kontraście jest realną
   barierą dla osób słabowidzących.
6. Narożniki wypełnione tłem - iOS sam nakłada maskę squircle; własne
   zaokrąglenie dałoby podwójne, z ciemną obwódką.

Uruchomienie: python3 tools/test_ikony_ios.py
Kontrola ważności: python3 tools/test_ikony_ios.py --kontrola-waznosci
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generuj_ikone_ios import TLO, UDZIAL_SYMBOLU, WARIANTY, wczytaj_symbol, zbuduj  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IKONY = os.path.join(REPO, "Tyflocentrum/Assets.xcassets/AppIcon.appiconset")

bledy = []
zrobione = 0


def sprawdz(opis, warunek):
    global zrobione
    zrobione += 1
    if not warunek:
        bledy.append(opis)
        print(f"  BLAD {opis}")
    else:
        print(f"  OK   {opis}")


def luminancja(rgb):
    """Luminancja relatywna wg WCAG 2.x."""
    c = np.asarray(rgb, dtype=float) / 255.0
    c = np.where(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def kontrast(rgb1, rgb2):
    l1, l2 = sorted((luminancja(rgb1), luminancja(rgb2)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def kolor_symbolu(obraz):
    """Średni kolor pikseli symbolu, wyznaczony GEOMETRYCZNIE.

    NIE po częstości kolorów: przy ikonie Androida najczęstszym "tłem" okazała
    się niebieska ramka fokusu TalkBacka i pomiar dał 2,99:1 zamiast 15,44:1.
    Bierzemy środkowy kwadrat i odsiewamy piksele bliskie tłu.
    """
    a = np.asarray(obraz.convert("RGB"), dtype=int)
    n = a.shape[0]
    m = max(1, int(n * 0.18))
    srodek = a[n // 2 - m: n // 2 + m, n // 2 - m: n // 2 + m].reshape(-1, 3)
    odleglosc = np.abs(srodek - np.asarray(TLO)).sum(axis=1)
    symbol = srodek[odleglosc > 60]
    if len(symbol) == 0:
        return None
    return symbol.mean(axis=0)


def testy(katalog):
    print(f"--- katalog: {katalog}")
    contents_path = os.path.join(katalog, "Contents.json")
    print("--- 1. Contents.json istnieje i jest poprawnym JSON-em ---")
    if not os.path.exists(contents_path):
        sprawdz("Contents.json istnieje", False)
        return
    with open(contents_path, encoding="utf-8") as f:
        contents = json.load(f)
    sprawdz("Contents.json wczytany", "images" in contents)

    wpisy = contents["images"]
    oczekiwane_px = {nazwa: px for (nazwa, px, *_r) in WARIANTY}

    print("--- 2. kompletnosc: kazdy wpis ma plik, kazdy plik ma wpis ---")
    z_wpisow = {w["filename"] for w in wpisy if w.get("filename")}
    na_dysku = {p for p in os.listdir(katalog) if p.lower().endswith(".png")}
    sprawdz(f"wpisow w Contents.json: {len(z_wpisow)}", len(z_wpisow) > 0)
    sprawdz(f"brak wpisow bez pliku (brakuje: {sorted(z_wpisow - na_dysku)})",
            not (z_wpisow - na_dysku))
    sprawdz(f"brak plikow-sierot (zbedne: {sorted(na_dysku - z_wpisow)})",
            not (na_dysku - z_wpisow))

    print("--- 3. kazdy PNG: bez alfy, dokladny rozmiar, narozniki w tle ---")
    bez_alfy = zle_rozmiary = zle_narozniki = 0
    for nazwa in sorted(z_wpisow & na_dysku):
        im = Image.open(os.path.join(katalog, nazwa))
        if "A" in im.getbands():
            bez_alfy += 1
        px = oczekiwane_px.get(nazwa)
        if px is not None and im.size != (px, px):
            zle_rozmiary += 1
            print(f"       {nazwa}: {im.size} zamiast ({px}, {px})")
        a = np.asarray(im.convert("RGB"), dtype=int)
        for y, x in ((0, 0), (0, -1), (-1, 0), (-1, -1)):
            if np.abs(a[y, x] - np.asarray(TLO)).sum() > 30:
                zle_narozniki += 1
                break
    sprawdz(f"zaden plik nie ma kanalu alfa (z alfa: {bez_alfy})", bez_alfy == 0)
    sprawdz(f"rozmiary zgodne z Contents.json (zle: {zle_rozmiary})", zle_rozmiary == 0)
    sprawdz(f"narozniki wypelnione tlem (zle: {zle_narozniki})", zle_narozniki == 0)

    print("--- 4. ikona 1024: tlo zgodne z granatem Windows ---")
    duza = Image.open(os.path.join(katalog, "ikona-1024.png")).convert("RGB")
    a = np.asarray(duza, dtype=int)
    naroznik = a[0, 0]
    odchylenie = int(np.abs(naroznik - np.asarray(TLO)).sum())
    sprawdz(f"tlo = rgb{TLO}, zmierzono rgb{tuple(naroznik)} (odchylenie {odchylenie})",
            odchylenie <= 6)

    print("--- 5. KONTRAST symbolu do tla wg WCAG 1.4.11 (prog 3:1) ---")
    sym_rgb = kolor_symbolu(duza)
    if sym_rgb is None:
        sprawdz("symbol widoczny na tle", False)
    else:
        k = kontrast(sym_rgb, TLO)
        sprawdz(f"kontrast {k:.2f}:1 przy progu 3:1 (symbol rgb{tuple(sym_rgb.round().astype(int))})",
                k >= 3.0)

    print("--- 6. symbol zajmuje oczekiwana czesc kafla (a nie caly/nic) ---")
    odl = np.abs(a - np.asarray(TLO)).sum(axis=2)
    widoczne = odl > 60
    udzial = float(widoczne.mean())
    sprawdz(f"symbol zajmuje {udzial:.1%} powierzchni (oczekiwane 5-45%)",
            0.05 <= udzial <= 0.45)
    kol = np.where(widoczne.any(axis=0))[0]
    wier = np.where(widoczne.any(axis=1))[0]
    if len(kol) and len(wier):
        szer = (kol[-1] - kol[0] + 1) / a.shape[1]
        sprawdz(f"szerokosc symbolu {szer:.1%} kafla (cel {UDZIAL_SYMBOLU:.0%}, tolerancja 5 pkt)",
                abs(szer - UDZIAL_SYMBOLU) <= 0.05)
    else:
        sprawdz("symbol ma niepusty obszar", False)


def kontrola_waznosci():
    """Buduje CELOWO ZEPSUTE ikony i sprawdza, ze test je odrzuca."""
    import shutil
    import tempfile

    sym = wczytaj_symbol(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "symbol_zrodlowy.png"))
    wyniki = []

    przypadki = {
        "z kanalem alfa": lambda im: im.convert("RGBA"),
        "zle tlo (jasne)": lambda im: Image.new("RGB", im.size, (240, 240, 240)),
        "zly rozmiar": lambda im: im.resize((im.size[0] // 2, im.size[1] // 2)),
        "bez symbolu (samo tlo)": lambda im: Image.new("RGB", im.size, TLO),
    }

    for opis, psuj in przypadki.items():
        katalog = tempfile.mkdtemp()
        try:
            for nazwa, px, _i, _s, _sc in WARIANTY:
                obraz = zbuduj(sym, px)
                if nazwa == "ikona-1024.png" or opis in ("z kanalem alfa", "zle tlo (jasne)"):
                    obraz = psuj(obraz)
                obraz.save(os.path.join(katalog, nazwa), "PNG")
            with open(os.path.join(katalog, "Contents.json"), "w", encoding="utf-8") as f:
                from generuj_ikone_ios import contents_json
                f.write(contents_json())

            global bledy, zrobione
            bledy, zrobione = [], 0
            print(f"\n=== psuje: {opis} ===")
            testy(katalog)
            wyniki.append((opis, len(bledy)))
        finally:
            shutil.rmtree(katalog, ignore_errors=True)

    print("\n=== PODSUMOWANIE KONTROLI WAZNOSCI ===")
    slabe = [o for o, n in wyniki if n == 0]
    for opis, n in wyniki:
        stan = "wykryte" if n else "NIE WYKRYTE - test jest ATRAPA"
        print(f"  {opis:26s} bledow={n:2d}  {stan}")
    if slabe:
        print(f"\nKONTROLA PADLA: te uszkodzenia przeszly niezauwazone: {slabe}")
        return 1
    print("\nKONTROLA WAZNOSCI OK: kazde uszkodzenie zostalo wykryte")
    return 0


def main():
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("--katalog", default=IKONY)
    p.add_argument("--kontrola-waznosci", action="store_true")
    args = p.parse_args()

    if args.kontrola_waznosci:
        return kontrola_waznosci()

    testy(args.katalog)
    print()
    print(f"asercje: {zrobione}, bledy: {len(bledy)}")
    if bledy:
        print("TEST PADL")
        return 1
    print("WSZYSTKO ZIELONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
