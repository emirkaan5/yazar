#!/bin/bash
# Resets Yazar to the state of a fresh install for local demos.
set -euo pipefail

bundle_id="egeis.yazar"
keychain_service="ai.yazar.openrouter"
keychain_account="api-key"

pkill -x yazar 2>/dev/null || true

if defaults read "$bundle_id" >/dev/null 2>&1; then
  defaults delete "$bundle_id"
fi

if security find-generic-password \
  -s "$keychain_service" \
  -a "$keychain_account" >/dev/null 2>&1; then
  security delete-generic-password \
    -s "$keychain_service" \
    -a "$keychain_account" >/dev/null
fi

tccutil reset Microphone "$bundle_id"
tccutil reset Accessibility "$bundle_id"

echo "reset Yazar preferences, API key, and privacy permissions"
echo "to demo Globe key setup, change 'Press Globe key to' away from 'Do Nothing' in System Settings"
