#!/usr/bin/env bash
# Sets up Sippier's Android release key. Every APK must be signed with it, or
# Android won't install it as an update: users would have to uninstall, and
# lose their accounts. Keep the keystore and its password in your password
# manager.
#
# With no keystore at the path, it creates one and asks for the key's alias,
# validity and password and the certificate's details. With one there (made
# with Android Studio, say), it uses that and asks for its passwords.
# Either way it gives the key to the release workflow as GitHub secrets, and
# writes app/android/key.properties (not in git) so local release builds are
# signed with it too.
#
# Usage: scripts/android-release-key.sh [keystore]
#   keystore  default ~/.android/keystores/sippier.jks
set -euo pipefail

REPO=codejo-dev/sippier
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE=${1:-$HOME/.android/keystores/sippier.jks}
PROPERTIES="$ROOT/app/android/key.properties"

die() {
  echo "$*" >&2
  exit 1
}

# Android Studio's JDK when there's no keytool on PATH
KEYTOOL=$(command -v keytool ||
  echo "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool")
[[ -x $KEYTOOL ]] || die "keytool not found; install a JDK"
gh auth status >/dev/null || die "sign in to GitHub first: gh auth login"

# keytool reads the passwords from these, so they're never on a command line
export STORE_PASSWORD KEY_PASSWORD

if [[ -e $KEYSTORE ]]; then
  echo "Using $KEYSTORE"
  read -rsp "Keystore password: " STORE_PASSWORD
  echo
  entries=$("$KEYTOOL" -list -keystore "$KEYSTORE" -storepass:env STORE_PASSWORD) ||
    die "can't open $KEYSTORE with that password"
  aliases=$(awk -F', ' '/PrivateKeyEntry/ { print $1 }' <<< "$entries")
  if [[ $(grep -c . <<< "$aliases") == 1 ]]; then
    ALIAS=$aliases
  else
    echo "Keys in it: $(tr '\n' ' ' <<< "$aliases")"
    read -rp "Key alias: " ALIAS
  fi
  read -rsp "Key password (Enter if it's the keystore password): " KEY_PASSWORD
  echo
  KEY_PASSWORD=${KEY_PASSWORD:-$STORE_PASSWORD}
  # A wrong key password would otherwise only show in the release workflow
  "$KEYTOOL" -certreq -keystore "$KEYSTORE" -alias "$ALIAS" \
    -storepass:env STORE_PASSWORD -keypass:env KEY_PASSWORD -file /dev/null ||
    die "can't use the key $ALIAS with that password"
else
  echo "Creating $KEYSTORE"
  read -rp "Key alias [sippier]: " ALIAS
  ALIAS=${ALIAS:-sippier}
  # Android doesn't check the expiry when installing or updating. Google
  # Play wants keys valid past 2033, Android's docs 25 years or more.
  read -rp "Valid for how many years [100]: " YEARS
  YEARS=${YEARS:-100}
  if [[ ! $YEARS =~ ^[0-9]+$ ]] || ((YEARS < 25)); then
    die "at least 25 years, please"
  fi
  read -rsp "Password (Enter to generate one): " STORE_PASSWORD
  echo
  if [[ -z $STORE_PASSWORD ]]; then
    STORE_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
  else
    ((${#STORE_PASSWORD} >= 6)) || die "keytool needs at least 6 characters"
    if LC_ALL=C grep -q '[^ -~]' <<< "$STORE_PASSWORD"; then
      die "PKCS12 keystores take only ASCII letters, digits and symbols"
    fi
    read -rsp "Password again: " again
    echo
    [[ $again == "$STORE_PASSWORD" ]] || die "the passwords differ"
  fi
  # PKCS12 keystores use one password for the store and the key
  KEY_PASSWORD=$STORE_PASSWORD

  if [[ ! -d $(dirname "$KEYSTORE") ]]; then
    mkdir -p "$(dirname "$KEYSTORE")"
    chmod 700 "$(dirname "$KEYSTORE")"
  fi
  echo "The certificate's details, shown to anyone who inspects the APK:"
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 \
    -alias "$ALIAS" -keyalg RSA -keysize 4096 \
    -validity $((YEARS * 36525 / 100)) \
    -storepass:env STORE_PASSWORD -keypass:env KEY_PASSWORD
  chmod 600 "$KEYSTORE"
fi

# A properties file reads \ as an escape
esc() { printf '%s' "${1//\\/\\\\}"; }
umask 077
cat > "$PROPERTIES" <<EOF
storeFile=$(esc "$KEYSTORE")
storePassword=$(esc "$STORE_PASSWORD")
keyAlias=$(esc "$ALIAS")
keyPassword=$(esc "$KEY_PASSWORD")
EOF

base64 < "$KEYSTORE" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 -R "$REPO"
printf %s "$STORE_PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD -R "$REPO"
printf %s "$ALIAS" | gh secret set ANDROID_KEY_ALIAS -R "$REPO"
printf %s "$KEY_PASSWORD" | gh secret set ANDROID_KEY_PASSWORD -R "$REPO"

echo
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass:env STORE_PASSWORD | grep -E '^(Owner|Valid from|[[:space:]]*SHA256):'
cat <<EOF

$PROPERTIES is written and the release workflow has the key as secrets.

Back up now, in your password manager:
  - the file $KEYSTORE
  - its password, in $PROPERTIES
EOF
