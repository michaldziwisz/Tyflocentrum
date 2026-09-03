#!/usr/bin/env python3
"""Sprawdz, czy zrzuty ekranu spelniaja wymogi App Store Connect.

Blad w rozmiarze albo kanal alfa wychodza normalnie DOPIERO przy wysylce do
Apple - czyli najpozniej, jak mozna. Ten skrypt przesuwa wykrycie do CI.

Rozmiary i zakaz alfy wprost z developer.apple.com, "Screenshot specifications":
  iPhone 6.9" : 1320x2868, 1290x2796, 1260x2736 (pion; poziom to zamienione osie)
  iPad 13"    : 2064x2752, 2048x2732
  "Images can't include alpha channels or transparencies."

Uzycie:
  sprawdz_zrzuty.py <katalog>                # wymaga OBU klas urzadzen
  sprawdz_zrzuty.py <katalog> --tylko-iphone # gdy swiadomie robimy jedna klase
  sprawdz_zrzuty.py --test                   # test wlasny z kontrola waznosci
"""
import argparse
import glob
import os
import struct
import sys

IPHONE_69 = {(1320, 2868), (1290, 2796), (1260, 2736)}
IPAD_13 = {(2064, 2752), (2048, 2732)}

# Typy koloru PNG z kanalem alfa: 4 = szarosc+alfa, 6 = RGBA.
TYPY_Z_ALFA = (4, 6)


def wymiary_png(sciezka):
    """Zwroc ((szerokosc, wysokosc), typ_koloru) albo (None, None)."""
    with open(sciezka, "rb") as f:
        naglowek = f.read(26)
    if naglowek[:8] != b"\x89PNG\r\n\x1a\n":
        return None, None
    szer, wys = struct.unpack(">II", naglowek[16:24])
    return (szer, wys), naglowek[25]


def klasa(rozmiar):
    """Nazwa klasy urzadzenia albo None. Akceptuje tez orientacje pozioma."""
    szer, wys = rozmiar
    obrocony = (wys, szer)
    if rozmiar in IPHONE_69 or obrocony in IPHONE_69:
        return "iPhone 6.9"
    if rozmiar in IPAD_13 or obrocony in IPAD_13:
        return "iPad 13"
    return None


def sprawdz(katalog, wymagaj_ipada=True, min_na_klase=1, cicho=False):
    """Zwroc (lista_problemow, licznik_klas)."""
    pliki = sorted(glob.glob(os.path.join(katalog, "*.png")))
    problemy = []
    licznik = {"iPhone 6.9": 0, "iPad 13": 0}

    if not pliki:
        return ["brak plikow PNG w katalogu %s" % katalog], licznik

    if not cicho:
        print("%-56s %-14s %-5s %s" % ("plik", "rozmiar", "alfa", "werdykt"))
    for sciezka in pliki:
        rozmiar, typ = wymiary_png(sciezka)
        nazwa = os.path.basename(sciezka)
        if rozmiar is None:
            problemy.append(f"{nazwa}: to nie jest plik PNG")
            continue
        ma_alfe = typ in TYPY_Z_ALFA
        k = klasa(rozmiar)
        if k:
            licznik[k] += 1
            werdykt = f"{k} OK"
        else:
            werdykt = "ROZMIAR NIEZGODNY"
            problemy.append(
                f"{nazwa}: {rozmiar[0]}x{rozmiar[1]} nie jest rozmiarem App Store")
        if ma_alfe:
            problemy.append(f"{nazwa}: ma kanal alfa (Apple odrzuca)")
        if not cicho:
            print("%-56s %-14s %-5s %s" % (
                nazwa, f"{rozmiar[0]}x{rozmiar[1]}",
                "tak" if ma_alfe else "nie", werdykt))

    if licznik["iPhone 6.9"] == 0:
        problemy.append("brak zrzutow dla iPhone 6.9 (wymagane dla apki na iPhone)")
    elif licznik["iPhone 6.9"] < min_na_klase:
        problemy.append(
            f"iPhone 6.9: tylko {licznik['iPhone 6.9']} zrzutow, oczekiwano "
            f"co najmniej {min_na_klase}")
    if wymagaj_ipada:
        if licznik["iPad 13"] == 0:
            problemy.append(
                "brak zrzutow dla iPad 13 (wymagane, bo TARGETED_DEVICE_FAMILY = \"1,2\")")
        elif licznik["iPad 13"] < min_na_klase:
            # Ten warunek wylapal realna awarie: na iPadzie z iOS 26 kolekcja
            # app.tabBars jest pusta (system renderuje TabView jako panel boczny),
            # wiec test przerywal po PIERWSZYM ekranie i mielismy 1 zrzut zamiast 5.
            # Bez progu "co najmniej N" bramka mowila wtedy "wszystko zgodne".
            problemy.append(
                f"iPad 13: tylko {licznik['iPad 13']} zrzutow, oczekiwano co "
                f"najmniej {min_na_klase} - sprawdz, czy test nie przerwal sie "
                f"po pierwszym ekranie")
    return problemy, licznik


def test_wlasny():
    """Kontrola waznosci: kazdy przypadek poprawny ma pare NIEPOPRAWNA."""
    import tempfile
    import zlib

    def zrob_png(sciezka, szer, wys, z_alfa):
        """Minimalny, poprawny PNG o zadanych wymiarach."""
        typ = 6 if z_alfa else 2  # 6 = RGBA, 2 = RGB
        def kawalek(tag, dane):
            return (struct.pack(">I", len(dane)) + tag + dane
                    + struct.pack(">I", zlib.crc32(tag + dane) & 0xFFFFFFFF))
        ihdr = struct.pack(">IIBBBBB", szer, wys, 8, typ, 0, 0, 0)
        kanaly = 4 if z_alfa else 3
        surowe = b"".join(b"\x00" + b"\x00" * (szer * kanaly) for _ in range(wys))
        with open(sciezka, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
            f.write(kawalek(b"IHDR", ihdr))
            f.write(kawalek(b"IDAT", zlib.compress(surowe)))
            f.write(kawalek(b"IEND", b""))

    bledy = []
    zrobione = 0

    def asercja(opis, warunek):
        nonlocal zrobione
        zrobione += 1
        if warunek:
            print(f"  OK   {opis}")
        else:
            print(f"  BLAD {opis}")
            bledy.append(opis)

    print("--- 1. POZYTYW: komplet poprawnych zrzutow przechodzi ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 1320, 2868, False)
        zrob_png(os.path.join(kat, "ipad-1.png"), 2064, 2752, False)
        problemy, licznik = sprawdz(kat, cicho=True)
        asercja(f"komplet bez problemow (dostano: {problemy})", not problemy)
        asercja("policzony 1 iPhone i 1 iPad",
                licznik["iPhone 6.9"] == 1 and licznik["iPad 13"] == 1)

    print("--- 2. NEGATYW: kanal alfa MUSI byc odrzucony ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 1320, 2868, True)
        zrob_png(os.path.join(kat, "ipad-1.png"), 2064, 2752, False)
        problemy, _ = sprawdz(kat, cicho=True)
        asercja("alfa wykryta", any("alfa" in p for p in problemy))

    print("--- 3. NEGATYW: zly rozmiar MUSI byc odrzucony ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 1179, 2556, False)  # 6.3", nie 6.9"
        zrob_png(os.path.join(kat, "ipad-1.png"), 2064, 2752, False)
        problemy, _ = sprawdz(kat, cicho=True)
        asercja("niezgodny rozmiar wykryty",
                any("nie jest rozmiarem" in p for p in problemy))

    print("--- 4. NEGATYW: brak iPada MUSI byc zglaszany (apka na iPhone+iPad) ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 1320, 2868, False)
        problemy, _ = sprawdz(kat, cicho=True)
        asercja("brak iPada wykryty", any("iPad 13" in p for p in problemy))
        problemy2, _ = sprawdz(kat, wymagaj_ipada=False, cicho=True)
        asercja("z --tylko-iphone brak iPada NIE jest bledem", not problemy2)

    print("--- 5. NEGATYW: 11-calowy iPad to NIE klasa 13 (pulapka prefiksu) ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 1320, 2868, False)
        zrob_png(os.path.join(kat, "ipad-1.png"), 1488, 2266, False)  # 11"
        problemy, licznik = sprawdz(kat, cicho=True)
        asercja("iPad 11 nie liczy sie jako 13", licznik["iPad 13"] == 0)
        asercja("i jest zglaszany jako problem", bool(problemy))

    print("--- 5b. NEGATYW: NIEPELNY komplet z iPada (test urwal sie po 1. ekranie) ---")
    # To jest przypadek, ktory realnie wystapil (run 33782945660): na iPadzie
    # app.tabBars jest puste w iOS 26, wiec powstal 1 zrzut zamiast 5, a bramka
    # bez progu min_na_klase orzekla "wszystko zgodne".
    with tempfile.TemporaryDirectory() as kat:
        for i in range(5):
            zrob_png(os.path.join(kat, f"iphone-{i}.png"), 1320, 2868, False)
        zrob_png(os.path.join(kat, "ipad-1.png"), 2064, 2752, False)
        bez_progu, _ = sprawdz(kat, cicho=True)
        asercja(f"przy progu 1 niepelny komplet PRZECHODZI (dostano: {bez_progu})",
                not bez_progu)
        z_progiem, _ = sprawdz(kat, min_na_klase=4, cicho=True)
        asercja("przy progu 4 niepelny komplet jest WYKRYTY",
                any("tylko 1 zrzutow" in p for p in z_progiem))

    print("--- 6. orientacja pozioma jest dopuszczalna ---")
    with tempfile.TemporaryDirectory() as kat:
        zrob_png(os.path.join(kat, "iphone-1.png"), 2868, 1320, False)
        zrob_png(os.path.join(kat, "ipad-1.png"), 2752, 2064, False)
        problemy, licznik = sprawdz(kat, cicho=True)
        asercja(f"poziome zrzuty przyjete (dostano: {problemy})", not problemy)

    print("--- 7. NEGATYW: pusty katalog ---")
    with tempfile.TemporaryDirectory() as kat:
        problemy, _ = sprawdz(kat, cicho=True)
        asercja("pusty katalog zglaszany", bool(problemy))

    print()
    print(f"asercje: {zrobione}, bledy: {len(bledy)}")
    if bledy:
        print("TEST PADL")
        return 1
    print("WSZYSTKO ZIELONE")
    return 0


def main():
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("katalog", nargs="?", default="artefakty")
    p.add_argument("--tylko-iphone", action="store_true",
                   help="nie wymagaj zrzutow iPada")
    p.add_argument("--min-na-klase", type=int, default=1,
                   help="ile zrzutow musi byc w KAZDEJ klasie urzadzen "
                        "(domyslnie 1; workflow uzywa 4, zeby wylapac test "
                        "przerwany po pierwszym ekranie)")
    p.add_argument("--test", action="store_true",
                   help="uruchom test wlasny z kontrola waznosci")
    args = p.parse_args()

    if args.test:
        return test_wlasny()

    problemy, licznik = sprawdz(args.katalog,
                                wymagaj_ipada=not args.tylko_iphone,
                                min_na_klase=args.min_na_klase)
    print()
    print(f"zrzutow iPhone 6.9: {licznik['iPhone 6.9']}, iPad 13: {licznik['iPad 13']}")
    if problemy:
        print("\nPROBLEMY:")
        for x in problemy:
            print("  -", x)
        return 1
    print("\nWSZYSTKO ZGODNE z wymogami App Store.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
