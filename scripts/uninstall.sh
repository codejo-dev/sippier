#!/bin/bash
# Uninstalls Sippier from macOS: the app, its accounts, settings, call
# history and log, the account passwords in the keychain, and its microphone
# permission:
#
#   curl -fsSL https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/uninstall.sh | bash
#
# Sippier is sandboxed, so its data is in its own container. macOS may ask
# whether your terminal may access data from other apps: that's this script
# reaching into the container.
#
# Everything is in main, so a partial download through the pipe runs nothing.

main() {
  set -euo pipefail

  local id=dev.codejo.sippier
  # Everything Sippier writes is in its container's Data. macOS keeps the
  # container folder itself, with its metadata, out of a script's reach.
  local container=$HOME/Library/Containers/$id
  local data=$container/Data
  local scripts="$HOME/Library/Application Scripts/$id"
  local accounts="$data/Library/Application Support/$id/accounts.json"
  local access="macOS didn't give your terminal access to Sippier's data. Allow it when asked, or turn on Full Disk Access for your terminal app in System Settings > Privacy & Security, then run this again."

  [[ $(uname -s) == Darwin ]] ||
    die "this is for macOS; for Windows see https://github.com/codejo-dev/sippier#uninstalling"

  local app apps=0
  for app in /Applications/Sippier.app "$HOME/Applications/Sippier.app"; do
    if [[ $(bundle_id "$app") == "$id" ]]; then apps=$((apps + 1)); fi
  done
  if [[ $apps == 0 && ! -e $data && ! -e $scripts ]]; then
    echo "Sippier isn't installed"
    return
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

  # The passwords are in the login keychain, under the service "Sippier": all
  # of them, one at a time
  local removed=0 _
  for _ in $(seq 100); do
    security delete-generic-password -s Sippier >/dev/null 2>&1 || break
    removed=$((removed + 1))
  done
  # Up to 0.1.0-beta.2 under the service name every Flutter app's secure
  # storage shares, so there only those of Sippier's accounts
  if [[ -f $accounts ]]; then
    local ids account
    ids=$(account_ids "$accounts" 2>/dev/null) || die "$access"
    for account in $ids; do
      if security delete-generic-password -s flutter_secure_storage_service \
        -a "password.$account" >/dev/null 2>&1; then
        removed=$((removed + 1))
      fi
    done
  fi
  if [[ $removed -gt 0 ]]; then
    echo "Removed $removed account password(s) from the keychain"
  fi

  # Microphone and any other privacy permission
  tccutil reset All "$id" >/dev/null 2>&1 || true

  if [[ -e $data || -e $scripts ]]; then
    # Fails on the container's metadata, which may stay
    rm -rf "$container" "$scripts" 2>/dev/null || true
    [[ ! -e $data && ! -e $scripts ]] || die "$access"
    echo "Removed Sippier's accounts, settings, call history and log"
  fi

  for app in /Applications/Sippier.app "$HOME/Applications/Sippier.app"; do
    if [[ $(bundle_id "$app") == "$id" ]]; then
      rm -rf "$app" || die "couldn't remove $app"
      echo "Removed $app"
    fi
  done

  echo "Sippier is uninstalled"
}

die() {
  echo "sippier: $*" >&2
  exit 1
}

# bundle_id <app>: the app's bundle identifier, empty if there's no such app
bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# account_ids <accounts.json>: the ids of the saved accounts, one per line
account_ids() {
  osascript -l JavaScript - "$1" <<'JS'
function run(argv) {
  var text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  return JSON.parse(text).accounts.map(function (a) { return a.id; }).join('\n');
}
JS
}

main "$@"
