#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
cd "$repo_root"

product_name="Codexkit"
product_slug="codexkit"
default_version_label="$(git -C "$repo_root" describe --tags --always --dirty 2>/dev/null || date -u +local-%Y%m%dT%H%M%SZ)"
version_label="${CODEXKIT_RELEASE_VERSION:-${1:-$default_version_label}}"
version_slug="$(print -r -- "$version_label" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
if [[ -z "$version_slug" ]]; then
  version_slug="local-$(date -u +%Y%m%dT%H%M%SZ)"
fi

marketing_version="${CODEXKIT_MARKETING_VERSION:-$(python3 - "$version_label" <<'PY'
import re
import sys
value = sys.argv[1]
match = re.match(r'^v?(\d+\.\d+(?:\.\d+)?)', value)
print(match.group(1) if match else '0.0.0')
PY
)}"
build_number="${CODEXKIT_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
bundle_identifier="${CODEXKIT_BUNDLE_IDENTIFIER:-com.codexkit.app}"
configuration="${CODEXKIT_BUILD_CONFIGURATION:-release}"
release_dir="${CODEXKIT_RELEASE_DIR:-$repo_root/dist/release}"
release_notes_url="${CODEXKIT_RELEASE_NOTES_URL:-https://github.com/lcc-project/Codexkit/releases}"
download_page_url="${CODEXKIT_DOWNLOAD_PAGE_URL:-$release_notes_url}"
lsui_element="${CODEXKIT_LSUIELEMENT:-1}"
adhoc_sign="${CODEXKIT_ADHOC_SIGN:-1}"
minimum_system_version="${CODEXKIT_MINIMUM_SYSTEM_VERSION:-14.0}"
published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "${CODEXKIT_RELEASE_ARCH:-$(uname -m)}" in
  arm64|aarch64)
    artifact_architecture="arm64"
    go_arch="arm64"
    ;;
  x86_64|amd64)
    artifact_architecture="x86_64"
    go_arch="amd64"
    ;;
  *)
    artifact_architecture="universal"
    go_arch=""
    ;;
esac

app_path="$release_dir/${product_name}.app"
zip_path="$release_dir/${product_slug}-${version_slug}-macOS-${artifact_architecture}.zip"
dmg_path="$release_dir/${product_slug}-${version_slug}-macOS-${artifact_architecture}.dmg"
manifest_path="$release_dir/release-manifest.json"
bundled_repo_root="$repo_root/Sources/CodexkitApp/Bundled/CLIProxyAPIServiceBundle/CLIProxyAPI"
bundled_bin_dir="$repo_root/Sources/CodexkitApp/Bundled/CLIProxyAPIServiceBundle/bin"
bundled_binary_path="$bundled_bin_dir/cli-proxy-api-darwin-${artifact_architecture}"

mkdir -p "$release_dir"
stale_temp_paths=("$release_dir"/.dmg-staging.*(N) "$release_dir"/.zip-check.*(N))
if (( ${#stale_temp_paths[@]} > 0 )); then
  rm -rf -- "${stale_temp_paths[@]}"
fi
rm -rf "$app_path" "$zip_path" "$dmg_path" "$manifest_path"

cleanup_paths=()
cleanup() {
  local cleanup_path
  for cleanup_path in "${cleanup_paths[@]:-}"; do
    [[ -e "$cleanup_path" ]] && rm -rf "$cleanup_path"
  done
}
trap cleanup EXIT

if [[ -z "$go_arch" ]]; then
  echo "unsupported release architecture: ${artifact_architecture}" >&2
  exit 1
fi
command -v go >/dev/null 2>&1 || { echo "missing required 'go' executable for bundled CLIProxyAPI build" >&2; exit 1; }
[[ -f "$bundled_repo_root/go.mod" ]] || { echo "missing bundled CLIProxyAPI module: $bundled_repo_root/go.mod" >&2; exit 1; }
mkdir -p "$bundled_bin_dir"
cleanup_paths+=("$bundled_binary_path")

printf '==> build bundled CLIProxyAPI (%s)\n' "$artifact_architecture"
(
  cd "$bundled_repo_root"
  CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" go build -o "$bundled_binary_path" ./cmd/server
)
chmod +x "$bundled_binary_path"

printf '==> swift build (%s)\n' "$configuration"
swift build -c "$configuration"

bin_dir="$(swift build -c "$configuration" --show-bin-path)"
binary_path="$bin_dir/$product_name"
resource_bundle_path="$bin_dir/${product_name}_CodexkitApp.bundle"
info_plist_template="$repo_root/Sources/CodexkitApp/Info.plist"

[[ -x "$binary_path" ]] || { echo "missing binary: $binary_path" >&2; exit 1; }
[[ -d "$resource_bundle_path" ]] || { echo "missing resource bundle: $resource_bundle_path" >&2; exit 1; }
[[ -f "$info_plist_template" ]] || { echo "missing Info.plist template: $info_plist_template" >&2; exit 1; }

printf '==> assemble app bundle\n'
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
ditto "$binary_path" "$app_path/Contents/MacOS/$product_name"
chmod +x "$app_path/Contents/MacOS/$product_name"
ditto "$resource_bundle_path" "$app_path/Contents/Resources/${resource_bundle_path:t}"

python3 - "$info_plist_template" "$app_path/Contents/Info.plist" "$bundle_identifier" "$product_name" "$marketing_version" "$build_number" "$minimum_system_version" "$published_at" "$version_label" "$lsui_element" "$release_notes_url" <<'PY'
import plistlib
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
bundle_identifier = sys.argv[3]
product_name = sys.argv[4]
marketing_version = sys.argv[5]
build_number = sys.argv[6]
minimum_system_version = sys.argv[7]
published_at = sys.argv[8]
version_label = sys.argv[9]
lsui_element = sys.argv[10] not in {"0", "false", "False", "no", "NO"}
release_notes_url = sys.argv[11]

with template_path.open('rb') as handle:
    plist = plistlib.load(handle)

plist.update({
    'CFBundleExecutable': product_name,
    'CFBundleIdentifier': bundle_identifier,
    'CFBundleName': product_name,
    'CFBundleDisplayName': product_name,
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': marketing_version,
    'CFBundleVersion': build_number,
    'LSMinimumSystemVersion': minimum_system_version,
    'LSUIElement': lsui_element,
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
    'CodexkitReleaseBuildLabel': version_label,
    'CodexkitReleaseBuiltAt': published_at,
    'CodexkitReleaseNotesURL': release_notes_url,
})

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open('wb') as handle:
    plistlib.dump(plist, handle, sort_keys=False)
PY

printf 'APPL????' > "$app_path/Contents/PkgInfo"

if [[ "$adhoc_sign" != "0" ]]; then
  printf '==> ad-hoc codesign\n'
  codesign --force --deep --sign - "$app_path"
fi

printf '==> create zip\n'
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

printf '==> create dmg\n'
dmg_staging_dir="$(mktemp -d "$release_dir/.dmg-staging.XXXXXX")"
cleanup_paths+=("$dmg_staging_dir")
ln -s /Applications "$dmg_staging_dir/Applications"
ditto "$app_path" "$dmg_staging_dir/${product_name}.app"
hdiutil create -quiet -fs HFS+ -volname "$product_name" -srcfolder "$dmg_staging_dir" -format UDZO "$dmg_path"

printf '==> write manifest\n'
zip_sha="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
dmg_sha="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
python3 - "$manifest_path" "$artifact_architecture" "$version_label" "$published_at" "$release_notes_url" "$download_page_url" "$zip_path" "$zip_sha" "$dmg_path" "$dmg_sha" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
architecture = sys.argv[2]
version_label = sys.argv[3]
published_at = sys.argv[4]
release_notes_url = sys.argv[5]
download_page_url = sys.argv[6]
zip_path = Path(sys.argv[7])
zip_sha = sys.argv[8]
dmg_path = Path(sys.argv[9])
dmg_sha = sys.argv[10]

manifest = {
    'schemaVersion': 1,
    'channel': 'local',
    'release': {
        'version': version_label,
        'publishedAt': published_at,
        'summary': 'Local acceptance build generated from the current Codexkit worktree.',
        'releaseNotesURL': release_notes_url,
        'downloadPageURL': download_page_url,
        'deliveryMode': 'guidedDownload',
        'artifacts': [
            {
                'architecture': architecture,
                'format': 'dmg',
                'fileName': dmg_path.name,
                'localPath': dmg_path.name,
                'sha256': dmg_sha,
            },
            {
                'architecture': architecture,
                'format': 'zip',
                'fileName': zip_path.name,
                'localPath': zip_path.name,
                'sha256': zip_sha,
            },
        ],
    },
}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

printf '==> smoke checks\n'
plutil -p "$app_path/Contents/Info.plist" >/dev/null
hdiutil imageinfo "$dmg_path" >/dev/null
zip_check_dir="$(mktemp -d "$release_dir/.zip-check.XXXXXX")"
cleanup_paths+=("$zip_check_dir")
ditto -x -k "$zip_path" "$zip_check_dir"
[[ -d "$zip_check_dir/${product_name}.app" ]] || { echo "zip smoke check failed" >&2; exit 1; }

printf '\nRelease artifacts ready:\n'
printf '  app: %s\n' "$app_path"
printf '  dmg: %s\n' "$dmg_path"
printf '  zip: %s\n' "$zip_path"
printf '  manifest: %s\n' "$manifest_path"
