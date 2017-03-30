#!/bin/bash
# This script simplifies adding a new admin PGP key, making user able to decrypt files with git-crypt.
# It uses keybase user id to simplify key exchange.
set -e

# Read configuration from CLI
while getopts "u:" opt; do
  case "$opt" in
    u)  KEYBASE_ID="${OPTARG}"
        ;;
  esac
done

if [ ! $KEYBASE_ID ]; then
  echo "[E] You need to specify Keybase user with '-u' option."
  exit 1
fi

echo "[I] Starting to follow ${KEYBASE_ID}"
keybase follow $KEYBASE_ID

echo "[I] Pulling ${KEYBASE_ID} pgp keys"
keybase pgp pull $KEYBASE_ID

echo "[I] Extracting ${KEYBASE_ID} GPG ID"
KEY=$(gpg --list-keys samorai | grep "pub" | awk '/pub/{if (length($2) > 0) print $2}')
KEY="${KEY##*/}"

if [ ! $KEYBASE_ID ]; then
  echo "[E] Can't find public key ID for ${KEYBASE_ID}."
  exit 1
fi

echo "[I] Adding git-crypt GPG user ${KEY}"
git-crypt add-gpg-user ${KEY}
