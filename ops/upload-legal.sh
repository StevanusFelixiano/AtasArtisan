#!/bin/bash
# Uploads legal/build/*.pdf to the public `legal` bucket as the review account. Needs the temporary
# legal_*_tmp storage policies (see CLAUDE.md) in place; drop them afterwards.
set -e
B=https://scgyssmzfurqjkgfomtq.supabase.co; K=sb_publishable_ihHWwF0eSLK1SSkR85lS_A_25gle_43
RC=$(security find-generic-password -s ataste.review-code -a ataste -w)
TH=$(curl -s -X POST "$B/functions/v1/otp/review" -H "apikey: $K" -H 'content-type: application/json' -d "{\"code\":\"$RC\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token_hash"])')
AT=$(curl -s -X POST "$B/auth/v1/verify" -H "apikey: $K" -H 'content-type: application/json' -d "{\"type\":\"magiclink\",\"token_hash\":\"$TH\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
cd "$(dirname "$0")/../legal/build"
for pair in privacy-policy:privacy terms-of-use:terms support:support; do
  src=${pair%%:*}; dst=${pair##*:}
  echo "$dst: $(curl -s -X POST "$B/storage/v1/object/legal/$dst.pdf" -H "apikey: $K" -H "Authorization: Bearer $AT" \
    -H 'content-type: application/pdf' -H 'x-upsert: true' -H 'cache-control: max-age=300' --data-binary @$src.pdf | head -c 80)"
done
