#!/usr/bin/env bash
# Zrzuty przyciskow odtwarzacza w DWOCH wariantach ustawien dostepnosci.
#
# PO CO. Zgloszenie od uzytkownikow: przyciski predkosci, znacznikow czasu i
# ulubionych sa slabo widoczne przy zwiekszonym kontrascie. Autor projektu jest
# niewidomy i nie zweryfikuje tego wzrokiem, wiec dowodem musi byc ZRZUT, ktory
# da sie obejrzec - i to w tym samym trybie, w ktorym zgloszono problem.
#
# Wariant "kontrast" wlacza przez simctl:
#   increase-contrast  - iOS wzmacnia obramowania i tla,
#   bold-text          - grubsza czcionka systemowa,
#   button-shapes      - iOS sam podkresla, co jest przyciskiem.
# Jesli po wlaczeniu tych trzech rzeczy przyciski NADAL sa nieczytelne, to znaczy,
# ze problem jest w naszym stylowaniu, a nie w ustawieniach uzytkownika.
#
# Uzycie: scripts/zrzuty-przyciskow.sh
set -uo pipefail

URZADZENIE="${URZADZENIE:-iPhone 17 Pro Max}"
PROJECT_PATH="${PROJECT_PATH:-Tyflocentrum.xcodeproj}"
SCHEME="${SCHEME:-Tyflocentrum}"
WYJSCIE="${WYJSCIE:-artefakty-przyciski}"
TMP="${RUNNER_TEMP:-/tmp}"

mkdir -p "$WYJSCIE"

if ! UDID="$(python3 scripts/udid_symulatora.py "$URZADZENIE")"; then
	echo "Nie znalazlem symulatora '$URZADZENIE'." >&2
	exit 1
fi
echo "udid: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b || true

ETYKIETA="$(echo "$URZADZENIE" | tr ' ()' '-' | tr -s '-' | sed 's/-$//')"

for WARIANT in domyslny kontrast; do
	echo "::group::wariant $WARIANT"

	if [ "$WARIANT" = "kontrast" ]; then
		# Ustawienia dostepnosci wlaczane po stronie SYMULATORA, nie aplikacji -
		# dlatego zrzut pokazuje to, co realnie widzi uzytkownik z tymi opcjami.
		xcrun simctl ui "$UDID" increase-contrast enabled || true
		xcrun simctl ui "$UDID" content-size accessibility-large || true
	else
		xcrun simctl ui "$UDID" increase-contrast disabled || true
		xcrun simctl ui "$UDID" content-size medium || true
	fi

	BUNDLE="$TMP/Przyciski-$ETYKIETA-$WARIANT.xcresult"
	rm -rf "$BUNDLE"

	xcodebuild \
		-project "$PROJECT_PATH" \
		-scheme "$SCHEME" \
		-configuration Debug \
		-sdk iphonesimulator \
		-destination "platform=iOS Simulator,id=$UDID" \
		-derivedDataPath "$TMP/DD-przyciski-$ETYKIETA" \
		-resultBundlePath "$BUNDLE" \
		-parallel-testing-enabled NO \
		-parallel-testing-worker-count 1 \
		-only-testing:TyflocentrumUITests/ZrzutyPrzyciskow \
		ETYKIETA_URZADZENIA="$ETYKIETA" \
		ETYKIETA_WARIANTU="$WARIANT" \
		test || echo "UWAGA: wariant $WARIANT zwrocil blad - zrzuty moga byc niekompletne"

	echo "::endgroup::"
done

if ! command -v xcparse >/dev/null 2>&1; then
	brew install chargepoint/xcparse/xcparse
fi

for BUNDLE in "$TMP"/Przyciski-*.xcresult; do
	[ -e "$BUNDLE" ] || continue
	echo "wyciagam zrzuty z $BUNDLE"
	xcparse screenshots "$BUNDLE" "$WYJSCIE/" || true
done

echo
echo "=== zrzuty w $WYJSCIE ==="
ls -la "$WYJSCIE" || true
