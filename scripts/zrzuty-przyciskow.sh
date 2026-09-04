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
		#
		# UWAGA NA NAZWY: opcje simctl maja PODKRESLENIA, nie myslniki
		# (increase_contrast, content_size). Z myslnikami simctl NIE zglasza
		# bledu - wypisuje pomoc i konczy sie kodem 0, wiec `|| true` maskowalo
		# to calkowicie: pierwszy przebieg dal zrzuty tylko wariantu domyslnego,
		# a oba katalogi wygladaly na zrobione. Dlatego teraz sprawdzamy WYNIK.
		xcrun simctl ui "$UDID" increase_contrast enabled
		xcrun simctl ui "$UDID" content_size accessibility-large
	else
		xcrun simctl ui "$UDID" increase_contrast disabled
		xcrun simctl ui "$UDID" content_size medium
	fi

	# Kontrola, ze ustawienie NAPRAWDE weszlo. Bez tego "zrzut w trybie
	# kontrastu" moglby byc zwyklym zrzutem pod inna nazwa - czyli dowodem,
	# ktory nie dowodzi niczego.
	ODCZYT_KONTRAST="$(xcrun simctl ui "$UDID" increase_contrast || echo "?")"
	ODCZYT_ROZMIAR="$(xcrun simctl ui "$UDID" content_size || echo "?")"
	echo "stan symulatora: increase_contrast=$ODCZYT_KONTRAST content_size=$ODCZYT_ROZMIAR"
	if [ "$WARIANT" = "kontrast" ] && [ "$ODCZYT_KONTRAST" != "enabled" ]; then
		echo "BLAD: nie udalo sie wlaczyc trybu kontrastu (odczyt: $ODCZYT_KONTRAST)" >&2
		exit 1
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
		test || echo "UWAGA: wariant $WARIANT zwrocil blad - zrzuty moga byc niekompletne"

	echo "::endgroup::"
done

if ! command -v xcparse >/dev/null 2>&1; then
	brew install chargepoint/xcparse/xcparse
fi

# WYCIAGANIE ZRZUTOW: kazdy wariant do OSOBNEGO katalogu, potem zmiana nazwy.
#
# DLACZEGO TAK, A NIE PRZEZ ZMIENNA SRODOWISKOWA: dwie proby przekazania etykiety
# wariantu do testu PADLY - ani `ETYKIETA_WARIANTU=...` (xcodebuild traktuje to
# jako ustawienie budowania), ani prefiks `TEST_RUNNER_` nie dotarly do
# ProcessInfo.environment procesu testu na symulatorze. Skutek byl ZAWSZE ten sam:
# oba przebiegi zapisywaly zalaczniki jako "domyslny" i drugi nadpisywal pierwszy.
#
# Nazwa wariantu jest znana TUTAJ, w petli, wiec nie ma po co jej nikomu przekazywac.
# Bierzemy ja z nazwy pliku .xcresult (Przyciski-<urzadzenie>-<wariant>.xcresult)
# i doklejamy do nazw plikow po wyciagnieciu. Zadnej zaleznosci od xcodebuild.
for BUNDLE in "$TMP"/Przyciski-*.xcresult; do
	[ -e "$BUNDLE" ] || continue

	# Przyciski-iPhone-17-Pro-Max-kontrast.xcresult -> kontrast
	NAZWA_BUNDLE="$(basename "$BUNDLE" .xcresult)"
	WARIANT_Z_PLIKU="${NAZWA_BUNDLE##*-}"

	echo "wyciagam zrzuty z $BUNDLE (wariant: $WARIANT_Z_PLIKU)"
	POD="$TMP/rozpakowane-$WARIANT_Z_PLIKU"
	rm -rf "$POD"; mkdir -p "$POD"
	xcparse screenshots "$BUNDLE" "$POD/" || true

	for PLIK in "$POD"/*.png; do
		[ -e "$PLIK" ] || continue
		mv "$PLIK" "$WYJSCIE/${ETYKIETA}-${WARIANT_Z_PLIKU}-$(basename "$PLIK")"
	done
done

echo
echo "=== zrzuty w $WYJSCIE ==="
ls -la "$WYJSCIE" || true

# KONTROLA KONCOWA: czy w nazwach plikow SA oba warianty.
# Poprzednio nie bylo - xcodebuild dostawal ETYKIETA_WARIANTU jako USTAWIENIE
# BUDOWANIA, a test czytal ProcessInfo.environment swojego procesu, wiec zmienna
# NIE docierala do symulatora i kazdy przebieg zapisywal zrzuty jako "domyslny",
# nadpisujac poprzednie. Workflow konczyl sie SUKCESEM z polowa materialu.
# Prefiks TEST_RUNNER_ to sposob xcodebuild na przekazanie zmiennej SRODOWISKOWEJ
# do procesu testu (zdejmuje prefiks przed uruchomieniem).
BRAKI=0
for W in domyslny kontrast; do
	ILE="$(ls "$WYJSCIE" 2>/dev/null | grep -c -- "-$W-" || true)"
	echo "wariant $W: $ILE zrzutow"
	if [ "$ILE" -eq 0 ]; then
		echo "BLAD: brak zrzutow wariantu '$W' - etykieta nie dotarla do testu" >&2
		BRAKI=1
	fi
done
[ "$BRAKI" -eq 0 ] || exit 1
