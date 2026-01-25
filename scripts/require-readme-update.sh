#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]; then
  echo "Usage: $0 <base_sha> <head_sha>" >&2
  exit 2
fi

if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  echo "::error::Base commit not found locally: $BASE_SHA (did you checkout with fetch-depth: 0?)" >&2
  exit 2
fi

if ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
  echo "::error::Head commit not found locally: $HEAD_SHA" >&2
  exit 2
fi

changed_files="$(git diff --name-only "$BASE_SHA...$HEAD_SHA")"

if [[ -z "${changed_files//[[:space:]]/}" ]]; then
  echo "No changed files detected between $BASE_SHA...$HEAD_SHA."
  exit 0
fi

docs_touched=false
requires_docs=false
trigger_files=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  case "$file" in
    README.md|docs/*)
      docs_touched=true
      ;;
  esac

  case "$file" in
    README.md|docs/*)
      continue
      ;;
  esac

  case "$file" in
    .github/workflows/readme-guard.yml|scripts/require-readme-update.sh)
      continue
      ;;
  esac

  case "$file" in
    Tyflocentrum/*)
      if [[ "$file" == *.md || "$file" == *.rtf ]]; then
        continue
      fi
      requires_docs=true
      trigger_files+=("$file")
      ;;
    Tyflocentrum.xcodeproj/*|Tyflocentrum.xcdatamodeld/*|.github/workflows/*|scripts/*|installers/*)
      requires_docs=true
      trigger_files+=("$file")
      ;;
  esac
done <<< "$changed_files"

if [[ "$requires_docs" == "true" && "$docs_touched" != "true" ]]; then
  {
    echo "::error::README.md is required for this change but was not updated."
    echo "::error::Update README.md (or add docs under docs/) when changing app/build/workflow/scripts."
    echo ""
    echo "Files triggering the requirement (first 50):"
    printf -- "- %s\n" "${trigger_files[@]:0:50}"
    echo ""
    echo "All changed files:"
    echo "$changed_files" | sed 's/^/- /'
  } >&2
  exit 1
fi

echo "README guard passed."
