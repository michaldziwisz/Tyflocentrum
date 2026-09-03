#!/usr/bin/env bash
# Zrzuty ekranu do karty App Store, robione na SYMULATORACH.
#
# PO CO. Apple wymaga zrzutow dla iPhone'a 6.9" oraz - skoro projekt ma
# TARGETED_DEVICE_FAMILY "1,2" - takze dla iPada 13". Michal ma iPhone'a, nie ma
# iPada, a kupowanie urzadzenia po to, zeby zrobic pare obrazkow, nie mialoby
# sensu. Runner macOS ma symulatory obu klas i zrzuty z nich sa pikselowo
# dokladne, wiec App Store Connect je przyjmuje.
#
# UWAGA TERMINOLOGICZNA: symulator to nie emulator. Nie emuluje procesora -
# uruchamia natywny kod na macOS i renderuje UIKit w prawdziwej rozdzielczosci
# urzadzenia. Dlatego wymiary zrzutow sa dokladnie takie, jak na sprzecie.
#
# Uzycie:
#   scripts/zrzuty-ekranu.sh                                  # domyslne dwa urzadzenia
#   URZADZENIA="iPhone 17 Pro Max,iPad Pro 13-inch (M5)" scripts/zrzuty-ekranu.sh
set -uo pipefail

URZADZENIA="${URZADZENIA:-iPhone 17 Pro Max,iPad Pro 13-inch (M5)}"
PROJECT_PATH="${PROJECT_PATH:-Tyflocentrum.xcodeproj}"
SCHEME="${SCHEME:-Tyflocentrum}"
WYJSCIE="${WYJSCIE:-artefakty}"
TMP="${RUNNER_TEMP:-/tmp}"

mkdir -p "$WYJSCIE"

IFS=',' read -ra LISTA <<<"$URZADZENIA"
for NAZWA in "${LISTA[@]}"; do
	# Obetnij spacje wokol nazwy (po przecinku zwykle jest spacja).
	NAZWA="$(echo "$NAZWA" | sed 's/^ *//;s/ *$//')"
	echo "::group::$NAZWA"

	# Dokladne dopasowanie nazwy, nie prefiks: "iPad Pro 11-inch" NIE spelnia
	# wymogu klasy 13", a przy dopasowaniu po prefiksie latwo w nie trafic.
	if ! UDID="$(python3 scripts/udid_symulatora.py "$NAZWA")"; then
		echo "Nie znalazlem symulatora '$NAZWA' - przerywam." >&2
		exit 1
	fi
	echo "udid: $UDID"

	# Jawny boot + bootstatus. Zimny symulator wywala runner testow bledem
	# "Application has termination assertions" - to WYSCIG, nie blad kodu.
	xcrun simctl boot "$UDID" 2>/dev/null || true
	xcrun simctl bootstatus "$UDID" -b || true

	ETYKIETA="$(echo "$NAZWA" | tr ' ()' '-' | tr -s '-' | sed 's/-$//')"
	BUNDLE="$TMP/Wynik-$ETYKIETA.xcresult"
	rm -rf "$BUNDLE"

	# ETYKIETA_URZADZENIA wchodzi do nazwy zalacznika, zeby po pobraniu bylo
	# widac, ktory zrzut jest z ktorego urzadzenia.
	xcodebuild \
		-project "$PROJECT_PATH" \
		-scheme "$SCHEME" \
		-configuration Debug \
		-sdk iphonesimulator \
		-destination "platform=iOS Simulator,id=$UDID" \
		-derivedDataPath "$TMP/DD-$ETYKIETA" \
		-resultBundlePath "$BUNDLE" \
		-parallel-testing-enabled NO \
		-parallel-testing-worker-count 1 \
		-only-testing:TyflocentrumUITests/ZrzutyEkranu \
		ETYKIETA_URZADZENIA="$ETYKIETA" \
		test || echo "UWAGA: przebieg dla '$NAZWA' zwrocil blad - zrzuty moga byc niekompletne"

	echo "::endgroup::"
done

# xcparse wyciaga zalaczniki z .xcresult. Zrzuty sa zapisane jako zalaczniki
# testu (XCTAttachment z lifetime .keepAlways), nie jako pliki na dysku.
if ! command -v xcparse >/dev/null 2>&1; then
	brew install chargepoint/xcparse/xcparse
fi

for BUNDLE in "$TMP"/Wynik-*.xcresult; do
	[ -e "$BUNDLE" ] || continue
	echo "wyciagam zrzuty z $BUNDLE"
	xcparse screenshots "$BUNDLE" "$WYJSCIE/" || true
done

echo
echo "=== zrzuty w $WYJSCIE ==="
ls -la "$WYJSCIE" || true
