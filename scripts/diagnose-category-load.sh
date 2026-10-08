#!/usr/bin/env bash
# TYFLO-CAT-DIAG: jeden pomiar, nigdy pętla do zielonego wyniku.
set -euo pipefail
EXPECTED='TyflocentrumUITests/TyflocentrumSmokeTests/testPullToRefreshUpdatesLists'
if [[ "${1:-}" != '--zapisz' || "${DIAG_TEST:-}" != "$EXPECTED" || "${DIAG_REPETITIONS:-}" != '1' ]]; then
    printf '%s
' 'Odmowa: wymagany --zapisz, dokładny scenariusz i jedno uruchomienie.' >&2
    exit 2
fi
OUT="$PWD/category-diagnostic"
mkdir -p "$OUT"
git rev-parse HEAD > "$OUT/head.txt"
xcodebuild -version > "$OUT/xcode.txt"
xcrun simctl list devices available -j > "$OUT/simulators.json"
# Ten sam model i runtime co w poprzedniej porażce, bez cichej zamiany.
SIM_ID="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["devices"]; rows=[x for runtime,items in d.items() if runtime.endswith("iOS-26-5") for x in items if x.get("isAvailable") and x["name"]=="iPhone 17 Pro"]; assert len(rows)==1, rows; print(rows[0]["udid"])' "$OUT/simulators.json")"
printf '%s
' "$SIM_ID" > "$OUT/simulator-id.txt"
set +e
xcodebuild     -project Tyflocentrum.xcodeproj     -scheme Tyflocentrum     -configuration Debug     -sdk iphonesimulator     -destination "platform=iOS Simulator,id=$SIM_ID"     -derivedDataPath "$RUNNER_TEMP/category-diagnostic-dd"     -resultBundlePath "$PWD/CategoryDiagnostic.xcresult"     -parallel-testing-enabled NO     -parallel-testing-worker-count 1     "-only-testing:$EXPECTED"     test > "$OUT/xcodebuild.log" 2>&1
RESULT=$?
printf '%s
' "$RESULT" > "$OUT/xcodebuild-exit.txt"
# Zapis w kontenerze aplikacji przeżywa zakończenie procesu przez XCTest.
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" net.tyflopodcast.tyflocentrum data 2> "$OUT/container-error.log")"
if [[ -n "$CONTAINER" && -f "$CONTAINER/Documents/category-load.jsonl" ]]; then
    cp "$CONTAINER/Documents/category-load.jsonl" "$OUT/category-load.jsonl"
else
    printf '%s
' 'BRAK śladu aplikacji; nie uznawać samego zielonego testu za zakończenie diagnozy.' > "$OUT/trace-missing.txt"
fi
xcrun simctl spawn "$SIM_ID" log show --style compact --last 20m     --predicate 'eventMessage CONTAINS "TYFLO-CAT-DIAG"' > "$OUT/unified.log" 2> "$OUT/unified-error.log"
if [[ -d CategoryDiagnostic.xcresult ]]; then
    xcrun xcresulttool export attachments --path CategoryDiagnostic.xcresult --output-path "$OUT/attachments" > "$OUT/export.log" 2>&1
    xcrun xcresulttool get test-results summary --path CategoryDiagnostic.xcresult > "$OUT/summary.json" 2> "$OUT/summary-error.log"
    xcrun xcresulttool get test-results tests --path CategoryDiagnostic.xcresult > "$OUT/tests.json" 2> "$OUT/tests-error.log"
fi
printf 'Wynik xcodebuild: %s. Jeden test, jedna próba. Odbiór wymaga analizy śladu.
' "$RESULT"
exit "$RESULT"
