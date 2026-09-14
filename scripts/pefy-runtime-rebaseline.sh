#!/usr/bin/env bash
set -euo pipefail

log() { printf '[PEFY-OPENCLAW] %s\n' "$*"; }
fail() { printf '[PEFY-OPENCLAW][FAIL] %s\n' "$*" >&2; exit "${2:-1}"; }

CANONICAL_UPSTREAM_URL="https://github.com/openclaw/openclaw.git"
UPSTREAM_URL="${PEFY_OPENCLAW_UPSTREAM_URL:-$CANONICAL_UPSTREAM_URL}"
UPSTREAM_BRANCH="${PEFY_OPENCLAW_UPSTREAM_BRANCH:-main}"
UPSTREAM_REF="refs/pefy/upstream/${UPSTREAM_BRANCH}"
EXPECTED_UPSTREAM_SHA="${PEFY_EXPECTED_UPSTREAM_SHA:-}"
EVIDENCE_DIR="${PEFY_OPENCLAW_EVIDENCE_DIR:-artifacts/pefy-openclaw-rebaseline}"
REPORT_ONLY="${PEFY_REBASELINE_REPORT_ONLY:-0}"

command -v git >/dev/null 2>&1 || fail "git is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
mkdir -p "$EVIDENCE_DIR"

if [[ "$UPSTREAM_URL" != "$CANONICAL_UPSTREAM_URL" ]]; then
  fail "Non-canonical upstream source rejected: expected $CANONICAL_UPSTREAM_URL" 7
fi

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

level_for_count() {
  local count="$1"
  if (( count == 0 )); then
    printf '0\n'
  elif (( count < 100 )); then
    printf '1\n'
  elif (( count < 1000 )); then
    printf '2\n'
  elif (( count < 10000 )); then
    printf '3\n'
  else
    printf '4\n'
  fi
}

UPSTREAM_LEVEL="$(level_for_count "$UPSTREAM_ONLY")"
DOWNSTREAM_LEVEL="$(level_for_count "$PEFY_ONLY")"
if (( UPSTREAM_LEVEL > DOWNSTREAM_LEVEL )); then
  REVIEW_LEVEL="$UPSTREAM_LEVEL"
else
  REVIEW_LEVEL="$DOWNSTREAM_LEVEL"
fi
UPSTREAM_DRIFT_CLASS="U${UPSTREAM_LEVEL}"
DOWNSTREAM_DIVERGENCE_CLASS="D${DOWNSTREAM_LEVEL}"
REVIEW_CLASS="R${REVIEW_LEVEL}"

LICENSE_FILE="$(mktemp)"
UPSTREAM_NOTICES_FILE="$(mktemp)"
trap 'rm -f "$LICENSE_FILE" "$UPSTREAM_NOTICES_FILE"' EXIT
git show "${UPSTREAM_REF}:LICENSE" > "$LICENSE_FILE" || fail "Canonical upstream LICENSE could not be read" 6
[[ -f LICENSE ]] || fail "PEFY candidate LICENSE is missing" 6

read -r PEFY_NOTICES_DECLARED UPSTREAM_NOTICES_DECLARED < <(
  python3 - LICENSE "$LICENSE_FILE" <<'PY'
from pathlib import Path
import sys

MIT_BODY = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""
APPROVED_NOTICE_SUFFIX = """Third-party notices for incorporated or adapted code are recorded in
THIRD_PARTY_NOTICES.md."""


def normalize(text: str) -> str:
    return "\n".join(line.rstrip() for line in text.replace("\r\n", "\n").strip().split("\n"))


def validate_mit(path: Path) -> bool:
    text = normalize(path.read_text(encoding="utf-8"))
    lines = text.split("\n")
    if not lines or lines[0].strip() != "MIT License":
        raise SystemExit(f"{path}: missing MIT License title")

    marker = "Permission is hereby granted, free of charge, to any person obtaining a copy"
    try:
        marker_index = lines.index(marker)
    except ValueError as exc:
        raise SystemExit(f"{path}: MIT permission clause missing") from exc

    preamble = [line.strip() for line in lines[1:marker_index] if line.strip()]
    if not preamble or any(not line.startswith("Copyright (c)") for line in preamble):
        raise SystemExit(f"{path}: unexpected text before MIT body")

    remaining = "\n".join(lines[marker_index:])
    if remaining == MIT_BODY:
        return False
    expected_with_notice = MIT_BODY + "\n\n" + APPROVED_NOTICE_SUFFIX
    if remaining == expected_with_notice:
        return True
    raise SystemExit(f"{path}: license content is not the approved SPDX MIT body or approved notices-pointer form")

pefy_notices = validate_mit(Path(sys.argv[1]))
upstream_notices = validate_mit(Path(sys.argv[2]))
print("true" if pefy_notices else "false", "true" if upstream_notices else "false")
PY
)

if [[ "$UPSTREAM_NOTICES_DECLARED" == "true" ]]; then
  git show "${UPSTREAM_REF}:THIRD_PARTY_NOTICES.md" > "$UPSTREAM_NOTICES_FILE" \
    || fail "Upstream LICENSE references THIRD_PARTY_NOTICES.md but the file is unavailable" 6
  [[ -s "$UPSTREAM_NOTICES_FILE" ]] || fail "Upstream THIRD_PARTY_NOTICES.md is empty" 6
fi
if [[ "$PEFY_NOTICES_DECLARED" == "true" ]]; then
  [[ -s THIRD_PARTY_NOTICES.md ]] \
    || fail "PEFY LICENSE references THIRD_PARTY_NOTICES.md but the file is unavailable or empty" 6
fi

hash_file() {
  python3 - "$1" <<'PY'
import hashlib
from pathlib import Path
import sys

path = Path(sys.argv[1])
h = hashlib.sha256()
with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

CURRENT_LICENSE_SHA256="$(hash_file LICENSE)"
UPSTREAM_LICENSE_SHA256="$(hash_file "$LICENSE_FILE")"
PEFY_NOTICES_SHA256=""
UPSTREAM_NOTICES_SHA256=""
if [[ "$PEFY_NOTICES_DECLARED" == "true" ]]; then
  PEFY_NOTICES_SHA256="$(hash_file THIRD_PARTY_NOTICES.md)"
fi
if [[ "$UPSTREAM_NOTICES_DECLARED" == "true" ]]; then
  UPSTREAM_NOTICES_SHA256="$(hash_file "$UPSTREAM_NOTICES_FILE")"
fi

if [[ "$REPORT_ONLY" == "1" ]]; then
  EVIDENCE_MODE="NON_QUALIFYING_EVIDENCE_ONLY"
else
  EVIDENCE_MODE="QUALIFICATION_DRIFT_GATE"
fi

cat > "$EVIDENCE_DIR/rebaseline.env" <<EOF
pefy_candidate_sha=$CURRENT_SHA
canonical_upstream_url=$CANONICAL_UPSTREAM_URL
canonical_source_verified=true
upstream_sha=$UPSTREAM_SHA
upstream_branch=$UPSTREAM_BRANCH
pefy_only_commits=$PEFY_ONLY
upstream_only_commits=$UPSTREAM_ONLY
upstream_drift_class=$UPSTREAM_DRIFT_CLASS
downstream_divergence_class=$DOWNSTREAM_DIVERGENCE_CLASS
review_class=$REVIEW_CLASS
pefy_license_sha256=$CURRENT_LICENSE_SHA256
upstream_license_sha256=$UPSTREAM_LICENSE_SHA256
repository_license=MIT
pefy_license_text_verified=true
upstream_license_text_verified=true
pefy_third_party_notices_declared=$PEFY_NOTICES_DECLARED
upstream_third_party_notices_declared=$UPSTREAM_NOTICES_DECLARED
pefy_third_party_notices_sha256=$PEFY_NOTICES_SHA256
upstream_third_party_notices_sha256=$UPSTREAM_NOTICES_SHA256
automatic_sync_performed=false
report_only=$REPORT_ONLY
evidence_mode=$EVIDENCE_MODE
EOF

python3 - "$EVIDENCE_DIR/rebaseline.json" "$CURRENT_SHA" "$CANONICAL_UPSTREAM_URL" "$UPSTREAM_SHA" "$PEFY_ONLY" "$UPSTREAM_ONLY" "$UPSTREAM_DRIFT_CLASS" "$DOWNSTREAM_DIVERGENCE_CLASS" "$REVIEW_CLASS" "$CURRENT_LICENSE_SHA256" "$UPSTREAM_LICENSE_SHA256" "$PEFY_NOTICES_DECLARED" "$UPSTREAM_NOTICES_DECLARED" "$PEFY_NOTICES_SHA256" "$UPSTREAM_NOTICES_SHA256" "$REPORT_ONLY" "$EVIDENCE_MODE" <<'PY'
import datetime as dt
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
payload = {
    "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "pefy_candidate_sha": sys.argv[2],
    "canonical_upstream_url": sys.argv[3],
    "canonical_source_verified": True,
    "upstream_sha": sys.argv[4],
    "pefy_only_commits": int(sys.argv[5]),
    "upstream_only_commits": int(sys.argv[6]),
    "upstream_drift_class": sys.argv[7],
    "downstream_divergence_class": sys.argv[8],
    "review_class": sys.argv[9],
    "license": {
        "spdx": "MIT",
        "pefy_text_verified": True,
        "upstream_text_verified": True,
        "pefy_sha256": sys.argv[10],
        "upstream_sha256": sys.argv[11],
        "pefy_third_party_notices_declared": sys.argv[12] == "true",
        "upstream_third_party_notices_declared": sys.argv[13] == "true",
        "pefy_third_party_notices_sha256": sys.argv[14] or None,
        "upstream_third_party_notices_sha256": sys.argv[15] or None,
    },
    "automatic_sync_performed": False,
    "report_only": sys.argv[16] == "1",
    "evidence_mode": sys.argv[17],
}
out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

log "Drift: upstream=$UPSTREAM_DRIFT_CLASS ($UPSTREAM_ONLY), downstream=$DOWNSTREAM_DIVERGENCE_CLASS ($PEFY_ONLY), review=$REVIEW_CLASS"
log "License: approved SPDX MIT body verified independently for upstream and PEFY candidate"
log "Third-party notices: upstream=$UPSTREAM_NOTICES_DECLARED, PEFY=$PEFY_NOTICES_DECLARED"
log "Canonical source: $CANONICAL_UPSTREAM_URL"
log "No upstream merge/rebase/sync was performed"

if [[ "$REPORT_ONLY" == "1" ]]; then
  log "NON-QUALIFYING evidence-only mode: no production qualification can be inferred from this successful run"
  exit 0
fi

if (( REVIEW_LEVEL >= 4 )); then
  fail "$REVIEW_CLASS drift requires controlled rebaseline, security review and benchmark evidence before production qualification" 4
fi

log "Rebaseline drift gate passed; security, CI, benchmark and real-host runtime gates are still required"
