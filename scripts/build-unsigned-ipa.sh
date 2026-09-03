#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Tyflocentrum.xcodeproj}"
SCHEME="${SCHEME:-Tyflocentrum}"
SWIFTFORMAT_VERSION="${SWIFTFORMAT_VERSION:-0.58.7}"
SIM_DESTINATION="${SIM_DESTINATION:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${RUNNER_TEMP:-$PWD}/DerivedData-${GITHUB_RUN_ID:-local}}"
# Wynik testow (.xcresult) laduje w katalogu roboczym, zeby workflow mogl go
# wystawic jako artefakt. Tam sa zalaczniki, w tym zrzuty ekranu z padajacych
# testow UI - bez nich diagnoza padniecia sprowadza sie do zgadywania.
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-$PWD/WynikTestow.xcresult}"
RUN_TESTS="${RUN_TESTS:-true}"
RUN_ARCHIVE="${RUN_ARCHIVE:-true}"

ensure_swiftformat() {
	# WAŻNE: wersja MUSI być przypięta. Formatowanie kodu to nie test poprawności,
	# tylko zgodność z konkretnym wydaniem narzędzia — kolejne wydania SwiftFormat
	# dodają i zmieniają reguły, więc niezmieniony plik zaczyna oblewać lint sam
	# z siebie. Tak zczerwieniało to CI: przebieg z 29.01.2026 był zielony,
	# a marcowy i czerwcowy padały po 13 sekundach, mimo że np.
	# Tyflocentrum/SettingsStore.swift nie był w tym czasie tknięty.
	# Zmierzone na tym repo (binarka linuksowa, WSL): 0.58.7 => 1/63 plików
	# do formatowania, 0.63.0 => 22/63.
	#
	# Dlatego NIE używamy `brew install swiftformat` (daje najnowszą wersję)
	# ani gołego `command -v swiftformat` (na runnerze bywa preinstalowany).
	# Zawsze bierzemy DOKŁADNIE tę wersję i sprawdzamy, co dostaliśmy.
	local tool_cache="${RUNNER_TOOL_CACHE:-$PWD/.tool-cache}"
	local swiftformat_dir="$tool_cache/swiftformat/$SWIFTFORMAT_VERSION"
	local swiftformat_bin="$swiftformat_dir/swiftformat"

	if [[ ! -x "$swiftformat_bin" ]]; then
		mkdir -p "$swiftformat_dir"

		local tmp_dir
		tmp_dir="$(mktemp -d)"

		# swiftformat.zip = macOS; swiftformat_linux.zip = Linux (przydaje się
		# przy sprawdzaniu lintu poza runnerem macOS).
		local asset="swiftformat.zip"
		if [[ "$(uname -s)" == "Linux" ]]; then
			asset="swiftformat_linux.zip"
		fi

		local url="https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/$asset"
		curl -fsSL -o "$tmp_dir/swiftformat.zip" "$url"
		unzip -q "$tmp_dir/swiftformat.zip" -d "$swiftformat_dir"
		rm -rf "$tmp_dir"

		# Archiwum linuksowe rozpakowuje się jako `swiftformat_linux`.
		if [[ ! -f "$swiftformat_bin" && -f "$swiftformat_dir/swiftformat_linux" ]]; then
			mv "$swiftformat_dir/swiftformat_linux" "$swiftformat_bin"
		fi

		chmod +x "$swiftformat_bin"
	fi

	export PATH="$swiftformat_dir:$PATH"

	# Kontrola, że dostaliśmy przypiętą wersję, a nie coś z PATH. Bez tego
	# przypięcie jest tylko deklaracją: wystarczy inna binarka wcześniej
	# w PATH i cała powyższa ostrożność przestaje cokolwiek znaczyć.
	local got
	got="$(swiftformat --version 2>/dev/null | tr -d '[:space:]')"
	if [[ "$got" != "$SWIFTFORMAT_VERSION" ]]; then
		echo "SwiftFormat: oczekiwano $SWIFTFORMAT_VERSION, dostano '${got:-brak}'." >&2
		echo "Lint bez przypietej wersji nie jest miarodajny - przerywam." >&2
		exit 1
	fi
	echo "SwiftFormat $got (przypieta)"
}

resolve_sim_destination() {
	if [[ -n "$SIM_DESTINATION" ]]; then
		return
	fi

	local sim_info
	sim_info="$(
		xcrun simctl list devices available | awk '
			$1 == "--" && $2 == "iOS" {
				ios = $3
				next
			}
			$1 == "--" {
				ios = ""
				next
			}
				ios == "" {
					next
				}
				$1 == "iPhone" {
					line = $0
					sub(/^[ \t]+/, "", line)

					name = line
					sub(/ [(].*/, "", name)

					if (!match(line, /[(][0-9A-Fa-f-]+[)]/)) {
						next
					}
					id = substr(line, RSTART + 1, RLENGTH - 2)
					if (first_id[ios] == "") {
						first_id[ios] = id
						first_name[ios] = name
					}
				}
				END {
					best_any = ""
					best_any_weight = -1
					best_stable = ""
					best_stable_weight = -1

					for (v in first_id) {
						w = ver_weight(v)
						if (w > best_any_weight) {
							best_any_weight = w
							best_any = v
						}

						split(v, parts, ".")
						major = parts[1] + 0
						if (major < 20 && w > best_stable_weight) {
							best_stable_weight = w
							best_stable = v
						}
					}

					if (best_stable != "") {
						best = best_stable
					} else {
						best = best_any
					}

					if (best == "" || first_id[best] == "") {
						exit 1
					}

					printf "%s\t%s\t%s\n", best, first_id[best], first_name[best]
				}
				function ver_weight(v, parts, n, major, minor, patch) {
					n = split(v, parts, ".")
					major = parts[1] + 0
					minor = (n >= 2 ? parts[2] + 0 : 0)
					patch = (n >= 3 ? parts[3] + 0 : 0)
					return major * 1000000 + minor * 1000 + patch
				}
			' || true
		)"

	if [[ -z "$sim_info" ]]; then
		echo "No available iPhone simulators found. Set SIM_DESTINATION env var (e.g. platform=iOS Simulator,name=iPhone 15)." >&2
		xcrun simctl list devices available || true
		exit 1
	fi

	local sim_os sim_id sim_name
	IFS=$'\t' read -r sim_os sim_id sim_name <<<"$sim_info"

	if [[ -z "${sim_id:-}" ]]; then
		echo "Failed to parse a simulator device ID from simctl output. Set SIM_DESTINATION env var." >&2
		xcrun simctl list devices available || true
		exit 1
	fi

	echo "Using simulator: $sim_name (iOS $sim_os) [$sim_id]"
	SIM_DESTINATION="platform=iOS Simulator,id=$sim_id"
}

echo "::group::Xcode version"
xcodebuild -version
echo "::endgroup::"

echo "::group::SwiftFormat (lint)"
ensure_swiftformat
swiftformat --config .swiftformat --lint .
echo "::endgroup::"

echo "::group::Bramki projektu (Python)"
# TE BRAMKI ISTNIALY, ALE NIC ICH NIE URUCHAMIALO. Byly opisane w dokumentacji
# i w APPSTORE_PROGRESS.md jako "dowod", a realnie nikt ich nie wolal na CI -
# czyli pilnowaly dokladnie tyle, ile plik lezacy na dysku. Klasyczny fałszywy
# dowod: raport mowi "sprawdzone", a pomiar nigdy nie biegnie.
#
# Kazda z nich sprawdza rzecz, ktora psuje sie CICHO (kod sie kompiluje, testy
# przechodza), a skutek widac dopiero przy wysylce do Apple albo u uzytkownika:
#   - konto_apple        : cudzy DEVELOPMENT_TEAM po merge z upstreamu,
#   - manifest_prywatnosci: brak deklaracji = odrzucenie przez App Store Connect,
#   - ikony_ios          : brakujacy rozmiar albo kanal alfa w ikonie,
#   - kontrast_przyciskow: kolor ponizej progu WCAG dla oslabionego wzroku,
#   - tytuly_zrzutow     : dane testowe na zrzutach wyslanych do sklepu.
#
# ZALEZNOSCI: test_ikony_ios analizuje piksele, wiec potrzebuje numpy i Pillow.
# Runner ich nie ma i pierwsze uruchomienie bramek na CI padlo wlasnie na tym
# (ModuleNotFoundError: numpy) - lokalnie przechodzilo, bo tu biblioteki sa.
# To zaleznosci NARZEDZI, nie aplikacji.
#
# DLACZEGO VENV, A NIE `pip install`: python3 z Homebrew (taki jest na runnerach
# macOS) jest "externally managed" wg PEP 668 i goly `pip install` konczy sie
# bledem, a `--break-system-packages` psuje srodowisko systemowe. Venv jest
# odporny na oba warianty i nie zalezy od tego, jak runner ma zbudowanego Pythona.
echo "--- srodowisko dla bramek"
BRAMKI_VENV="${RUNNER_TEMP:-/tmp}/venv-bramki"
if [[ ! -x "$BRAMKI_VENV/bin/python" ]]; then
	python3 -m venv "$BRAMKI_VENV"
fi
"$BRAMKI_VENV/bin/python" -m pip install --quiet --disable-pip-version-check numpy pillow
for bramka in \
	tools/test_konto_apple.py \
	tools/test_manifest_prywatnosci.py \
	tools/test_ikony_ios.py \
	tools/test_kontrast_przyciskow.py \
	tools/test_tytuly_zrzutow.py
do
	echo "--- $bramka"
	"$BRAMKI_VENV/bin/python" "$bramka"
done
echo "::endgroup::"

rm -rf "$DERIVED_DATA_PATH"

if [[ "$RUN_TESTS" == "true" ]]; then
	echo "::group::Test (Simulator)"
	resolve_sim_destination
	# -resultBundlePath: bez niego zalaczniki testow (w tym zrzuty ekranu
	# robione w tearDown przy PADNIECIU) zostaja w katalogu tymczasowym runnera
	# i przepadaja razem z maszyna. Padajacy test UI mowi wtedy tylko
	# "XCTAssertTrue failed w linii N", a nie CO bylo na ekranie - i kazda
	# kolejna poprawka jest zgadywaniem po 27 minutach na przebieg.
	rm -rf "$RESULT_BUNDLE_PATH"
	xcodebuild \
		-project "$PROJECT_PATH" \
		-scheme "$SCHEME" \
		-configuration Debug \
		-sdk iphonesimulator \
		-destination "$SIM_DESTINATION" \
		-derivedDataPath "$DERIVED_DATA_PATH" \
		-resultBundlePath "$RESULT_BUNDLE_PATH" \
		-parallel-testing-enabled NO \
		-parallel-testing-worker-count 1 \
		test
	echo "::endgroup::"
fi

if [[ "$RUN_ARCHIVE" == "true" ]]; then
	echo "::group::Archive (no codesign)"
	rm -rf build
	xcodebuild \
		-project "$PROJECT_PATH" \
		-scheme "$SCHEME" \
		-configuration Release \
		-sdk iphoneos \
		-destination 'generic/platform=iOS' \
		-archivePath build/Tyflocentrum.xcarchive \
		-derivedDataPath "$DERIVED_DATA_PATH" \
		archive \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY=""
	echo "::endgroup::"

	echo "::group::Create unsigned IPA"
	rm -rf Payload tyflocentrum.ipa
	mkdir -p Payload
	cp -R build/Tyflocentrum.xcarchive/Products/Applications/*.app Payload/
	/usr/bin/zip -r tyflocentrum.ipa Payload
	echo "::endgroup::"

	ls -lh tyflocentrum.ipa
fi
