#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <tag> <asset-directory>" >&2
  exit 64
fi

tag="$1"
asset_directory="$2"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

declare -a release_assets=(
  "PEeK-x64.msix|application/msix"
  "PEeK-x64.msix.sha256|text/plain"
  "PEeK.appinstaller|application/appinstaller"
)

for entry in "${release_assets[@]}"; do
  asset_name="${entry%%|*}"
  if [[ ! -f "$asset_directory/$asset_name" ]]; then
    echo "Release asset is missing: $asset_directory/$asset_name" >&2
    exit 66
  fi
done

if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" \
    --verify-tag \
    --generate-notes \
    --latest \
    --title "PEeK $tag"
fi

release_id="$(gh release view "$tag" --json databaseId --jq '.databaseId')"

upload_asset() {
  local asset_name="$1"
  local content_type="$2"
  local asset_path="$asset_directory/$asset_name"
  local existing_asset_id

  existing_asset_id="$(
    gh api --paginate \
      "repos/$repository/releases/$release_id/assets?per_page=100" \
      --jq ".[] | select(.name == \"$asset_name\") | .id" |
      head -n 1
  )"
  if [[ -n "$existing_asset_id" ]]; then
    gh api --method DELETE \
      "repos/$repository/releases/assets/$existing_asset_id"
  fi

  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "Accept: application/vnd.github+json" \
    --header "Authorization: Bearer $GH_TOKEN" \
    --header "X-GitHub-Api-Version: 2026-03-10" \
    --header "Content-Type: $content_type" \
    --data-binary "@$asset_path" \
    "https://uploads.github.com/repos/$repository/releases/$release_id/assets?name=$asset_name" \
    >/dev/null

  echo "Uploaded $asset_name as $content_type"
}

for entry in "${release_assets[@]}"; do
  upload_asset "${entry%%|*}" "${entry#*|}"
done
