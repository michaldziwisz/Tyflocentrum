#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Tyflocentrum.xcodeproj}"
SCHEME="${SCHEME:-Tyflocentrum}"
SIM_DESTINATION="${SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 15}"

echo "::group::Xcode version"
xcodebuild -version
echo "::endgroup::"

echo "::group::SwiftFormat (lint)"
if ! command -v swiftformat >/dev/null 2>&1; then
	if command -v brew >/dev/null 2>&1; then
		brew install swiftformat
	else
		echo "swiftformat not found and Homebrew is not available." >&2
		exit 1
	fi
fi
swiftformat --config .swiftformat --lint .
echo "::endgroup::"

echo "::group::Test (Simulator)"
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
