#!/usr/bin/env python3
"""Generuje komplet ikon iOS TyfloCentrum z symbolu ikony Windows/Android.

PO CO. Ujednolicamy identyfikację wizualną: Windows, Android i iOS mają mieć
tę samą ikonę. Wersja Androida (1.0.7) już ją ma; iOS wciąż nosi zupełnie inną
grafikę, odziedziczoną po pierwotnym autorze (pliki "App for Arek-*.png").

CZYM RÓŻNI SIĘ iOS OD ANDROIDA - to nie jest ten sam problem geometryczny:

1. BEZ PRZEZROCZYSTOŚCI. App Store odrzuca ikony z kanałem alfa. Zapisujemy
   RGB, nie RGBA. (Na Androidzie alfa jest normalna i potrzebna.)
2. BEZ WŁASNYCH ZAOKRĄGLEŃ. iOS sam nakłada maskę squircle na kwadratową
   grafikę. Gdybyśmy narysowali własny narożnik, dostalibyśmy zaokrąglenie
   podwójne, z ciemną obwódką. Dlatego tło jest PEŁNYM kwadratem - inaczej
   niż w bitmapach zapasowych Androida, gdzie squircle rysujemy sami.
3. BRAK STREFY BEZPIECZNEJ 66/108. Maska iOS jest znana i stała, więc symbol
   może być większy niż w adaptive icon Androida. Trzymamy 75% szerokości -
   tyle samo, ile ma oryginał z Windows, czyli wygląd jest 1:1 z kaflem.

Wynik: pliki PNG + Contents.json w Tyflocentrum/Assets.xcassets/AppIcon.appiconset.

Użycie:
    python3 tools/generuj_ikone_ios.py            # podgląd, NIC nie zapisuje
    python3 tools/generuj_ikone_ios.py --zapisz   # zapis do repo

Świadomie wymagamy jawnego --zapisz: narzędzie nadpisuje pliki w repo.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCELOWY = os.path.join(REPO, "Tyflocentrum/Assets.xcassets/AppIcon.appiconset")
SYMBOL_DOMYSLNY = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "symbol_zrodlowy.png")

# Granat kafla z wersji Windows, zmierzony na Square310x310Logo.png.
TLO = (2, 9, 29)
# Udział symbolu w szerokości kafla - jak w oryginale Windows.
UDZIAL_SYMBOLU = 0.75

# Komplet wymagany przez iOS. (nazwa_pliku, px, idiom, size, scale)
# Nazwy mówią, czym plik jest - stare "App for Arek-60@2x" nie mówiło nic.
WARIANTY = [
    ("ikona-20.png", 20, "ipad", "20x20", "1x"),
    ("ikona-20@2x.png", 40, "iphone", "20x20", "2x"),
    ("ikona-20@2x-ipad.png", 40, "ipad", "20x20", "2x"),
    ("ikona-20@3x.png", 60, "iphone", "20x20", "3x"),
    ("ikona-29.png", 29, "ipad", "29x29", "1x"),
    ("ikona-29@2x.png", 58, "iphone", "29x29", "2x"),
    ("ikona-29@2x-ipad.png", 58, "ipad", "29x29", "2x"),
    ("ikona-29@3x.png", 87, "iphone", "29x29", "3x"),
    ("ikona-40.png", 40, "ipad", "40x40", "1x"),
    ("ikona-40@2x.png", 80, "iphone", "40x40", "2x"),
    ("ikona-40@2x-ipad.png", 80, "ipad", "40x40", "2x"),
    ("ikona-40@3x.png", 120, "iphone", "40x40", "3x"),
    ("ikona-60@2x.png", 120, "iphone", "60x60", "2x"),
    ("ikona-60@3x.png", 180, "iphone", "60x60", "3x"),
    ("ikona-76.png", 76, "ipad", "76x76", "1x"),
    ("ikona-76@2x.png", 152, "ipad", "76x76", "2x"),
    ("ikona-83.5@2x.png", 167, "ipad", "83.5x83.5", "2x"),
    ("ikona-1024.png", 1024, "ios-marketing", "1024x1024", "1x"),
]


def wczytaj_symbol(sciezka):
    if not os.path.exists(sciezka):
        print(f"BRAK symbolu zrodlowego: {sciezka}", file=sys.stderr)
        print("To plik wyodrebniony z ikony Windows w projekcie Androida.", file=sys.stderr)
        sys.exit(2)
    sym = Image.open(sciezka).convert("RGBA")
    a = np.asarray(sym)
    if a[..., 3].max() == 0:
        print("Symbol jest calkowicie przezroczysty - to nie moze byc zrodlo.", file=sys.stderr)
        sys.exit(2)
    return sym


def zbuduj(sym, rozmiar_px):
    """Kwadratowe granatowe tło + symbol na środku, BEZ alfy i BEZ zaokrągleń.

    Nadpróbkowanie x4 przy skalowaniu symbolu: przy 20 px różnica między
    skalowaniem wprost a przez większe płótno jest widoczna na cienkich
    liniach symbolu.
    """
    sw, sh = sym.size
    ss = 4 if rozmiar_px < 256 else 1
    dp = rozmiar_px * ss

    plotno = Image.new("RGBA", (dp, dp), TLO + (255,))
    docelowa = dp * UDZIAL_SYMBOLU
    wsp = min(docelowa / sw, docelowa / sh)
    nw, nh = max(1, round(sw * wsp)), max(1, round(sh * wsp))
    maly = sym.resize((nw, nh), Image.LANCZOS)

    # alpha_composite, NIE paste z maską: paste miesza kanał alfa i robi
    # dziury w tle (błąd złapany przy ikonie Androida). Tu skutek byłby
    # jeszcze gorszy, bo iOS nie dopuszcza przezroczystości.
    nakladka = Image.new("RGBA", (dp, dp), (0, 0, 0, 0))
    nakladka.paste(maly, ((dp - nw) // 2, (dp - nh) // 2))
    plotno.alpha_composite(nakladka)

    if ss > 1:
        plotno = plotno.resize((rozmiar_px, rozmiar_px), Image.LANCZOS)

    # RGB: App Store odrzuca ikony z kanałem alfa.
    return plotno.convert("RGB")


def contents_json():
    obrazy = [
        {"filename": nazwa, "idiom": idiom, "scale": scale, "size": size}
        for (nazwa, _px, idiom, size, scale) in WARIANTY
    ]
    return json.dumps(
        {"images": obrazy, "info": {"author": "xcode", "version": 1}},
        indent=2,
        ensure_ascii=False,
    ) + "\n"


def main():
    p = argparse.ArgumentParser(
        description="Generuje ikony iOS TyfloCentrum z symbolu ikony Windows.",
        allow_abbrev=False,
    )
    p.add_argument("--symbol", default=SYMBOL_DOMYSLNY, help="PNG z symbolem (RGBA)")
    p.add_argument("--katalog", default=DOCELOWY, help="docelowy appiconset")
    p.add_argument("--zapisz", action="store_true", help="faktycznie zapisz pliki")
    args = p.parse_args()

    sym = wczytaj_symbol(args.symbol)
    print(f"symbol zrodlowy: {sym.size[0]}x{sym.size[1]}")
    print(f"tlo: rgb{TLO}, symbol {UDZIAL_SYMBOLU:.0%} szerokosci kafla")
    print(f"wariantow: {len(WARIANTY)}")

    if not args.zapisz:
        print()
        print("PODGLAD - nic nie zapisano. Dodaj --zapisz, zeby zapisac do:")
        print(f"  {args.katalog}")
        for nazwa, px, idiom, size, scale in WARIANTY:
            print(f"  {nazwa:24s} {px:4d}px  {idiom:13s} {size:11s} {scale}")
        return 0

    os.makedirs(args.katalog, exist_ok=True)
    for nazwa, px, _idiom, _size, _scale in WARIANTY:
        obraz = zbuduj(sym, px)
        sciezka = os.path.join(args.katalog, nazwa)
        obraz.save(sciezka, "PNG", optimize=True)
        print(f"  zapisano {nazwa} ({px}x{px})")

    with open(os.path.join(args.katalog, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(contents_json())
    print("  zapisano Contents.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
