#!/usr/bin/env bash
set -euo pipefail

log() { printf '[PEFY-OPENCLAW] %s\n' "$*"; }
fail() { printf '[PEFY-OPENCLAW][FAIL] %s\n' "$*" >&2; exit "${2:-1}"; }

UPSTREAM_URL="${PEFY_OPENCLAW_UPSTREAM_URL:-https://github.com/openclaw/openclaw.git}"
UPSTREAM_BRANCH="${PEFY_OPENCLAW_UPSTREAM_BRANCH:-main}"
UPSTREAM_REF="refs/pefy/upstream/${UPSTREAM_BRANCH}"
EXPECTED_UPSTREAM_SHA="${PEFY_EXPECTED_UPSTREAM_SHA:-}"
EVIDENCE_DIR="${PEFY_OPENCLAW_EVIDENCE_DIR:-artifacts/pefy-openclaw-rebaseline}"
REPORT_ONLY="${PEFY_REBASELINE_REPORT_ONLY:-0}"

command -v git >/dev/null 2>&1 || fail "git is required"
mkdir -p "$EVIDENCE_DIR"

CURRENT_SHA="$(git rev-parse HEAD)"
log "Current PEFY OpenClaw candidate: $CURRENT_SHA"
log "Fetching canonical upstream branch without merging"
git fetch --no-tags "$UPSTREAM_URL" "+refs/heads/${UPSTREAM_BRANCH}:${UPSTREAM_REF}"
UPSTREAM_SHA="$(git rev-parse "$UPSTREAM_REF")"
log "Canonical upstream candidate: $UPSTREAM_SHA"

if [[ -n "$EXPECTED_UPSTREAM_SHA" && "$UPSTREAM_SHA" != "$EXPECTED_UPSTREAM_SHA" ]]; then
  fail "Upstream moved: expected $EXPECTED_UPSTREAM_SHA but fetched $UPSTREAM_SHA; re-review before qualification" 5
fi

read -r PEFY_ONLY UPSTREAM_ONLY < <(git rev-list --left-right --count "HEAD...${UPSTREAM_REF}")

if (( UPSTREAM_ONLY == 0 )); then
  DRIFT_CLASS="U0"
elif (( UPSTREAM_ONLY < 100 )); then
  DRIFT_CLASS="U1"
elif (( UPSTREAM_ONLY < 1000 )); then
  DRIFT_CLASS="U2"
elif (( UPSTREAM_ONLY < 10000 )); then
  DRIFT_CLASS="U3"
else
  DRIFT_CLASS="U4"
fi

LICENSE_FILE="$(mktemp)"
trap 'rm -f "$LICENSE_FILE"' EXIT
git show "${UPSTREAM_REF}:LICENSE" > "$LICENSE_FILE" || fail "Canonical upstream LICENSE could not be read" 6
grep -q "MIT License" "$LICENSE_FILE" || fail "Expected MIT upstream license was not confirmed" 6

CURRENT_LICENSE_SHA256="$(sha256sum LICENSE | awk '{print $1}')"
UPSTREAM_LICENSE_SHA256="$(sha256sum "$LICENSE_FILE" | awk '{print $1}')"

cat > "$EVIDENCE_DIR/rebaseline.env" <<EOF
pefy_candidate_sha=$CURRENT_SHA
upstream_sha=$UPSTREAM_SHA
upstream_branch=$UPSTREAM_BRANCH
pefy_only_commits=$PEFY_ONLY
upstream_only_commits=$UPSTREAM_ONLY
drift_class=$DRIFT_CLASS
pefy_license_sha256=$CURRENT_LICENSE_SHA256
upstream_license_sha256=$UPSTREAM_LICENSE_SHA256
upstream_license=MIT
automatic_sync_performed=false
report_only=$REPORT_ONLY
EOF

python3 - "$EVIDENCE_DIR/rebaseline.json" "$CURRENT_SHA" "$UPSTREAM_SHA" "$PEFY_ONLY" "$UPSTREAM_ONLY" "$DRIFT_CLASS" "$CURRENT_LICENSE_SHA256" "$UPSTREAM_LICENSE_SHA256" "$REPORT_ONLY" <<'PY'
import datetime as dt
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
payload = {
    "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "pefy_candidate_sha": sys.argv[2],
    "upstream_sha": sys.argv[3],
    "pefy_only_commits": int(sys.argv[4]),
    "upstream_only_commits": int(sys.argv[5]),
    "drift_class": sys.argv[6],
    "license": {
        "spdx": "MIT",
        "pefy_sha256": sys.argv[7],
        "upstream_sha256": sys.argv[8],
    },
    "automatic_sync_performed": False,
    "report_only": sys.argv[9] == "1",
}
out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

log "Drift: $DRIFT_CLASS (PEFY-only=$PEFY_ONLY, upstream-only=$UPSTREAM_ONLY)"
log "License: MIT confirmed"
log "No upstream merge/rebase/sync was performed"

if [[ "$DRIFT_CLASS" == "U4" ]]; then
  if [[ "$REPORT_ONLY" == "1" ]]; then
    log "U4 recorded in governance report-only mode; runtime production qualification remains blocked"
    exit 0
  fi
  fail "U4 upstream drift requires controlled rebaseline, security review and benchmark evidence before production qualification" 4
fi

log "Drift gate passed; continue with security, CI, benchmark and runtime qualification"
