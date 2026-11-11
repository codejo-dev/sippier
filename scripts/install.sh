#!/bin/bash
# Installs or updates Sippier on macOS from the newest GitHub release,
# pre-releases included:
#
#   curl -fsSL https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/install.sh | bash
#
# The app isn't notarized yet. Apps a browser downloads get macOS's
# quarantine flag, and Gatekeeper refuses to open them; curl sets no such
# flag, so Sippier opens normally.
#
# Environment:
#   SIPPIER_VERSION  the release to install, e.g. v0.2.0 (default: newest)
#   GITHUB_TOKEN     optional: sent to GitHub's API, against its rate limit
#
# Everything is in main, so a partial download through the pipe runs nothing.

main() {
  set -euo pipefail

  local repo=codejo-dev/sippier
  local asset=Sippier-macos.zip
  local api="https://api.github.com/repos/$repo"

  [[ $(uname -s) == Darwin ]] ||
    die "this is for macOS; Windows and Android builds are at https://github.com/$repo/releases"
  # Also 1 in a shell running under Rosetta; Intel Macs don't have it
  [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]] ||
    die "Sippier needs a Mac with Apple silicon"

  # The repository is public, so no token is needed: a stale one (from gh,
  # say) would only make GitHub refuse
  local token=${GITHUB_TOKEN:-}
  auth=()
  if [[ -n $token ]]; then auth=(-H "Authorization: Bearer $token"); fi

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  local url="$api/releases?per_page=1"
  if [[ -n ${SIPPIER_VERSION:-} ]]; then url="$api/releases/tags/$SIPPIER_VERSION"; fi
  get "$url" application/vnd.github+json "$tmp/release.json" || die "no release found"

  local tag zip_url sums_url
  read -r tag zip_url sums_url < <(release_info "$tmp/release.json" "$asset") || true
  [[ -n ${tag:-} ]] || die "no release found"
  [[ $zip_url != - && $sums_url != - ]] || die "release $tag has no $asset"

  echo "Downloading Sippier $tag"
  get "$sums_url" application/octet-stream "$tmp/SHA256SUMS.txt" || die "download failed"
  get "$zip_url" application/octet-stream "$tmp/$asset" || die "download failed"

  local expected actual
  expected=$(awk -v f="$asset" '$2 == f { print $1 }' "$tmp/SHA256SUMS.txt")
  actual=$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')
  [[ -n $expected && $actual == "$expected" ]] || die "$asset doesn't match its checksum"

  ditto -x -k "$tmp/$asset" "$tmp/unpacked"
  [[ -d $tmp/unpacked/Sippier.app ]] || die "$asset has no Sippier.app"

  local dest=/Applications
  if [[ ! -w $dest ]]; then
    dest=$HOME/Applications
    mkdir -p "$dest"
  fi

  if pgrep -xq Sippier; then
    echo "Quitting Sippier"
    osascript -e 'quit app "Sippier"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -xq Sippier || break
      sleep 1
    done
    pkill -x Sippier || true
  fi

  rm -rf "$dest/Sippier.app"
  mv "$tmp/unpacked/Sippier.app" "$dest/"
  # In case anything set it: quarantined, the unnotarized app won't open
  xattr -dr com.apple.quarantine "$dest/Sippier.app" 2>/dev/null || true

  echo "Installed Sippier $tag in $dest"
  open "$dest/Sippier.app"
}

die() {
  echo "sippier: $*" >&2
  exit 1
}

# get <url> <accept> <file> [curl options...]
get() {
  local url=$1 accept=$2 file=$3
  shift 3
  # ${auth[@]+...}: an empty array is "unbound" for set -u in macOS's bash 3.2
  curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: $accept" -o "$file" "$@" "$url"
}

# release_info <release.json> <asset>: prints the tag and the API URLs of the
# asset and of SHA256SUMS.txt ("-" when missing). The JSON is a release, or a
# list of releases with the newest first.
release_info() {
  osascript -l JavaScript - "$1" "$2" <<'JS'
function run(argv) {
  var text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  var release = JSON.parse(text);
  if (Array.isArray(release)) release = release[0];
  if (!release) return '';
  function url(name) {
    var asset = (release.assets || []).filter(function (a) { return a.name === name; })[0];
    return asset ? asset.url : '-';
  }
  return [release.tag_name, url(argv[1]), url('SHA256SUMS.txt')].join(' ');
}
JS
}

main "$@"
