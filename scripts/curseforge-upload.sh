#!/usr/bin/env bash
# Upload one packaged addon zip to CurseForge.
#
# Extracted so the tag-driven release and the retry-by-hand workflow send the
# identical request. Two copies of an upload that runs a few times a month is
# two copies that quietly disagree by the time anyone looks.
#
#   usage: curseforge-upload.sh <zip> <display name>
#   env:   CF_TOKEN, CF_PROJECT, CF_VERSION_NAME, CF_VERSION_ID (optional)
set -euo pipefail

ZIP="${1:?usage: curseforge-upload.sh <zip> <display name>}"
NAME="${2:?usage: curseforge-upload.sh <zip> <display name>}"
: "${CF_TOKEN:?CF_TOKEN is not set}"
: "${CF_PROJECT:?CF_PROJECT is not set}"
CF_VERSION_NAME="${CF_VERSION_NAME:-2.5.6}"
CF_VERSION_ID="${CF_VERSION_ID:-}"

if [ -n "$CF_VERSION_ID" ]; then
  GV="$CF_VERSION_ID"
  echo "using the pinned game version id $GV"
else
  VERSIONS=$(curl -fsS "https://wow.curseforge.com/api/game/versions" \
    -H "X-Api-Token: $CF_TOKEN")
  HITS=$(echo "$VERSIONS" | jq -r --arg n "$CF_VERSION_NAME" \
    '[.[] | select(.name == $n) | .id] | @tsv')
  COUNT=$(echo "$HITS" | wc -w | tr -d ' ')
  # Exactly one match, or stop. CurseForge groups versions by client flavour,
  # so taking the first of several would quietly publish against the wrong one.
  if [ "$COUNT" != "1" ]; then
    echo "::error::Expected one CurseForge game version named '$CF_VERSION_NAME', found $COUNT."
    echo "$VERSIONS" | jq -r --arg n "${CF_VERSION_NAME%.*}" \
      '.[] | select(.name | startswith($n)) | "  \(.id)  \(.name)"'
    exit 1
  fi
  GV="$HITS"
  echo "resolved game version $CF_VERSION_NAME to id $GV"
fi

METADATA=$(jq -n --arg n "$NAME" --argjson gv "[$GV]" \
  '{changelog: "See the GitHub release notes.", changelogType: "text",
    displayName: $n, gameVersions: $gv, releaseType: "release"}')

# Not `curl -f`: that discards the response body, which is the only thing
# that explains a failure. A 500 here once cost a version bump to retry
# because the log said nothing but "error: 500". Capture both, then decide.
BODY=$(mktemp)
CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "https://wow.curseforge.com/api/projects/$CF_PROJECT/upload-file" \
  -H "X-Api-Token: $CF_TOKEN" \
  -F "metadata=$METADATA" \
  -F "file=@$ZIP")

if [ "$CODE" -ge 200 ] && [ "$CODE" -lt 300 ]; then
  echo "uploaded $NAME to project $CF_PROJECT: $(cat "$BODY")"
  rm -f "$BODY"
else
  echo "::error::CurseForge returned HTTP $CODE for $NAME"
  echo "--- response body ---"
  cat "$BODY"
  echo
  # 5xx is theirs and usually transient: the same zip can be re-sent with the
  # curseforge-upload workflow rather than by inventing a version number.
  if [ "$CODE" -ge 500 ]; then
    echo "A 5xx is CurseForge's side. Retry with:"
    echo "  gh workflow run curseforge-upload.yml -f tag=$NAME"
  fi
  rm -f "$BODY"
  exit 1
fi
