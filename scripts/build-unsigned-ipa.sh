#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Tyflocentrum.xcodeproj}"
SCHEME="${SCHEME:-Tyflocentrum}"
SWIFTFORMAT_VERSION="${SWIFTFORMAT_VERSION:-0.58.7}"
SIM_DESTINATION="${SIM_DESTINATION:-}"

ensure_swiftformat() {
	if command -v swiftformat >/dev/null 2>&1; then
		return
	fi

	if command -v brew >/dev/null 2>&1; then
		brew install swiftformat
		return
	fi

	local tool_cache="${RUNNER_TOOL_CACHE:-$PWD/.tool-cache}"
	local swiftformat_dir="$tool_cache/swiftformat/$SWIFTFORMAT_VERSION"
	local swiftformat_bin="$swiftformat_dir/swiftformat"

	if [[ ! -x "$swiftformat_bin" ]]; then
		mkdir -p "$swiftformat_dir"

		local tmp_dir
		tmp_dir="$(mktemp -d)"

		local url="https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip"
		curl -fsSL -o "$tmp_dir/swiftformat.zip" "$url"
		/usr/bin/unzip -q "$tmp_dir/swiftformat.zip" -d "$swiftformat_dir"
		chmod +x "$swiftformat_bin"
		rm -rf "$tmp_dir"
	fi

	export PATH="$swiftformat_dir:$PATH"
}

resolve_sim_destination() {
	if [[ -n "$SIM_DESTINATION" ]]; then
		return
	fi

	if xcrun simctl list devices available | grep -q "iPhone 15 ("; then
		SIM_DESTINATION="platform=iOS Simulator,name=iPhone 15"
		return
	fi

	local device_name
	device_name="$(xcrun simctl list devices available | sed -n 's/^[[:space:]]*\\(iPhone[^()]*\\) (.*$/\\1/p' | head -n 1)"
	if [[ -z "$device_name" ]]; then
		echo "No available iPhone simulators found. Set SIM_DESTINATION env var (e.g. platform=iOS Simulator,name=iPhone 15)." >&2
		xcrun simctl list devices available || true
		exit 1
	fi
	SIM_DESTINATION="platform=iOS Simulator,name=$device_name"
}

echo "::group::Xcode version"
xcodebuild -version
echo "::endgroup::"

echo "::group::SwiftFormat (lint)"
ensure_swiftformat
swiftformat --config .swiftformat --lint .
echo "::endgroup::"

echo "::group::Test (Simulator)"
resolve_sim_destination
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination "$SIM_DESTINATION" \
	-parallel-testing-enabled NO \
	-parallel-testing-worker-count 1 \
	test
echo "::endgroup::"

echo "::group::Archive (no codesign)"
rm -rf build
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration Release \
	-sdk iphoneos \
	-destination 'generic/platform=iOS' \
	-archivePath build/Tyflocentrum.xcarchive \
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
