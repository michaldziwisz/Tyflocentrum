#!/usr/bin/env bash
# Kontrola waznosci bramki wersji SwiftFormat w scripts/build-unsigned-ipa.sh.
#
# PO CO. CI tego repo bylo czerwone od marca do wrzesnia 2026, bo skrypt bral
# SwiftFormat z `brew install` (czyli najnowszy), a kolejne wydania dodaja
# reguly - niezmieniony plik zaczyna oblewac lint sam z siebie. Naprawa
# przypina wersje i SPRAWDZA, co dostala. Ten test dowodzi, ze sprawdzenie
# realnie dziala, a nie tylko istnieje w kodzie.
#
# Nie uruchamia buildu ani testow (wymagaja macOS) - wolamy sam
# ensure_swiftformat, z RUN_TESTS/RUN_ARCHIVE wylaczonymi.
set -uo pipefail

REPO="${REPO:-/mnt/d/projekty/tyflocentrum_ios}"
SKRYPT="$REPO/scripts/build-unsigned-ipa.sh"
PRACA="$(mktemp -d)"
trap 'rm -rf "$PRACA"' EXIT

bledy=0
zrobione=0

sprawdz() {
	local opis="$1" warunek="$2"
	zrobione=$((zrobione + 1))
	if [[ "$warunek" == "tak" ]]; then
		echo "  OK   $opis"
	else
		echo "  BLAD $opis"
		bledy=$((bledy + 1))
	fi
}

# Wyciagamy sama funkcje, zeby nie odpalac xcodebuild (nie ma go w WSL).
wyciagnij_funkcje() {
	sed -n '/^ensure_swiftformat() {/,/^}/p' "$SKRYPT"
}

echo "--- 1. wersja przypieta w skrypcie jest odczytywalna (tak jak w workflow) ---"
WERSJA="$(grep -oE 'SWIFTFORMAT_VERSION:-[0-9.]+' "$SKRYPT" | head -1 | cut -d- -f2-)"
[[ -n "$WERSJA" ]] && sprawdz "odczytano wersje: $WERSJA" tak || sprawdz "odczytano wersje" nie

echo "--- 2. skrypt NIE instaluje swiftformata przez brew (to bylo zrodlo awarii) ---"
# Szukamy WYKONYWANEJ instrukcji, nie wystapienia frazy: w skrypcie jest
# komentarz tlumaczacy, czemu brew tu nie uzywamy, i naiwny grep lapal wlasnie
# ten komentarz. Pomiar musi odrozniac kod od opisu kodu.
if grep -vE '^\s*#' "$SKRYPT" | grep -q 'brew install swiftformat'; then
	sprawdz "brak wywolania 'brew install swiftformat'" nie
else
	sprawdz "brak wywolania 'brew install swiftformat'" tak
fi

echo "--- 3. workflow formatujacy uzywa TEJ SAMEJ wersji co lint ---"
WF="$REPO/.github/workflows/swiftformat.yml"
if grep -vE '^\s*#' "$WF" | grep -q 'brew install swiftformat'; then
	sprawdz "workflow nie instaluje najnowszego przez brew" nie
else
	sprawdz "workflow nie instaluje najnowszego przez brew" tak
fi
if grep -q 'SWIFTFORMAT_VERSION' "$WF"; then
	sprawdz "workflow czyta wersje ze skryptu lintu (jedno zrodlo prawdy)" tak
else
	sprawdz "workflow czyta wersje ze skryptu lintu" nie
fi

echo "--- 4. POZYTYW: przy poprawnej wersji funkcja przechodzi ---"
{
	echo 'set -euo pipefail'
	echo "SWIFTFORMAT_VERSION=\"$WERSJA\""
	echo "RUNNER_TOOL_CACHE=\"$PRACA/cache\""
	wyciagnij_funkcje
	echo 'ensure_swiftformat'
} >"$PRACA/pozytyw.sh"
wynik="$(bash "$PRACA/pozytyw.sh" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && echo "$wynik" | grep -q "przypieta"; then
	sprawdz "poprawna wersja: kod 0 i meldunek o przypieciu" tak
else
	sprawdz "poprawna wersja: kod 0 (dostano rc=$rc: $(echo "$wynik" | tail -1))" nie
fi

echo "--- 5. KONTROLA NEGATYWNA: podstawiona ZLA binarka MUSI oblac ---"
# Kluczowa asercja. Klademy w cache atrape, ktora podaje inna wersje.
ZLE_CACHE="$PRACA/cache_zly/swiftformat/$WERSJA"
mkdir -p "$ZLE_CACHE"
printf '#!/usr/bin/env bash\necho 0.63.0\n' >"$ZLE_CACHE/swiftformat"
chmod +x "$ZLE_CACHE/swiftformat"
{
	echo 'set -uo pipefail'
	echo "SWIFTFORMAT_VERSION=\"$WERSJA\""
	echo "RUNNER_TOOL_CACHE=\"$PRACA/cache_zly\""
	wyciagnij_funkcje
	echo 'ensure_swiftformat'
} >"$PRACA/negatyw.sh"
wynik="$(bash "$PRACA/negatyw.sh" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then
	sprawdz "zla wersja binarki: NIEZEROWY kod wyjscia (rc=$rc)" tak
else
	sprawdz "zla wersja binarki: MUSI oblac, a przeszla - bramka jest ATRAPA" nie
fi
if echo "$wynik" | grep -q "oczekiwano $WERSJA"; then
	sprawdz "komunikat mowi, czego oczekiwano i co dostano" tak
else
	sprawdz "komunikat nazywa rozbieznosc wersji" nie
fi

echo
echo "asercje: $zrobione, bledy: $bledy"
if [[ $bledy -gt 0 ]]; then
	echo "TEST PADL"
	exit 1
fi
echo "WSZYSTKO ZIELONE"
