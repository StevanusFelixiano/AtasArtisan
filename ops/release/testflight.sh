#!/bin/sh
# After an upload: give build $1 to every external TestFlight group (Public, Invited), submit it for beta review,
# and once testers can install it, raise app_release.min_build so older TestFlight builds must update.
# Uses the App Store Connect session in Orca's browser: the account has no App Store Connect API access.
# Run it in the background; beta review can take hours.
set -eu
b=${1:?usage: testflight.sh <build number>}
js=$(sed "s/__BUILD__/$b/" "$(dirname "$0")/testflight.js")
page=$(orca tab create --url https://appstoreconnect.apple.com/apps --json | sed -n 's/.*"browserPageId": "\(.*\)".*/\1/p')
trap 'orca tab close --page "$page" >/dev/null 2>&1' EXIT
sleep 8
i=0
while :; do
  state=$(orca eval --page "$page" --expression "$js" | tail -1)
  echo "$(date +%H:%M) build $b: $state"
  case $state in
    IN_BETA_TESTING) break ;;
    WAIT|READY_FOR_BETA_SUBMISSION|WAITING_FOR_BETA_REVIEW|IN_BETA_REVIEW|BETA_APPROVED|PROCESSING_EXCEPTION|MISSING_EXPORT_COMPLIANCE) ;;
    *) echo "stopping: unexpected state (signed out of App Store Connect, or the build was rejected)"; exit 1 ;;
  esac
  i=$((i + 1)); [ $i -lt 144 ] || { echo "gave up after 24 h"; exit 1; }
  sleep 600; orca reload --page "$page" >/dev/null; sleep 8
done
PGPASSWORD="$(security find-generic-password -s ataste.db-password -a ataste -w)" /opt/homebrew/opt/libpq/bin/psql \
  "host=aws-0-ap-northeast-1.pooler.supabase.com port=5432 user=postgres.scgyssmzfurqjkgfomtq dbname=postgres" \
  -c "update public.app_release set min_build = greatest(min_build, $b) where channel = 'testflight'"
