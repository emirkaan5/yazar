#!/bin/bash
# Resets Yazar to the state of a fresh install for local demos.
set -euo pipefail

bundle_id="egeis.yazar"
keychain_service="ai.yazar.credentials"
# Accounts are TranscriptionProvider raw values; add new providers here.
keychain_accounts=(openRouter)
# The single-slot layout Yazar shipped first, cleared too so a reset is a reset
# even on a machine that has not launched the migrating build yet.
legacy_keychain_service="ai.yazar.openrouter"
legacy_keychain_account="api-key"

pkill -x yazar 2>/dev/null || true

if defaults read "$bundle_id" >/dev/null 2>&1; then
  defaults delete "$bundle_id"
fi

delete_password() {
  if security find-generic-password -s "$1" -a "$2" >/dev/null 2>&1; then
    security delete-generic-password -s "$1" -a "$2" >/dev/null
  fi
}

for account in "${keychain_accounts[@]}"; do
  delete_password "$keychain_service" "$account"
done
delete_password "$legacy_keychain_service" "$legacy_keychain_account"

tccutil reset Microphone "$bundle_id"
tccutil reset Accessibility "$bundle_id"

echo "reset Yazar preferences, API key, and privacy permissions"
echo "to demo Globe key setup, change 'Press Globe key to' away from 'Do Nothing' in System Settings"
