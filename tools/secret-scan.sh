#!/usr/bin/env bash
# Fail if anything that looks like a secret is about to be committed.
set -uo pipefail
R=${1:-$(cd "$(dirname "$0")/.." && pwd)}; cd "$R"
bad=0
files=$(git ls-files -co --exclude-standard)
# 1) forbidden file names
echo "$files" | grep -Ei '(authme-password|rclone\.conf|\.env$|cos\.env|notify\.env|id_(rsa|ed25519)$|ssh_host_.*_key$|\.pem$|\.key$|authme\.db|ops\.json|whitelist\.json|usercache\.json)' && { echo "FAIL: forbidden file"; bad=1; }
# 2) content patterns
pat='BEGIN [A-Z ]*PRIVATE KEY|AKID[A-Za-z0-9]{13,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[abp]-|(access_key|secret_access_key|secret_key|SecretKey)\s*=\s*[A-Za-z0-9/+]{16,}|^rcon\.password=(?!__REDACTED__).+|^management-server-secret=(?!__REDACTED__).+|WEBHOOK_(URL|KEY)=[^\s`"$]{8,}|Bearer [A-Za-z0-9._-]{20,}|https://[^ ]*(sig=|token=|tempauth=)[^ ]+'
hits=$(echo "$files" | xargs -d '\n' grep -nIP "$pat" 2>/dev/null | grep -v '^tools/secret-scan.sh:')
[[ -n "$hits" ]] && { echo "$hits" | cut -c1-200; echo "FAIL: secret-like content"; bad=1; }
# 2b) long random-looking tokens outside known-benign files (sha256 pins, Cargo.lock checksums, mrpack)
ent=$(echo "$files" | grep -vE '(^|/)(Cargo\.lock|PLUGINS\.md|[^/]*\.mrpack)$' | python3 -c '
import re, sys
for f in sys.stdin.read().split():
    try: lines = open(f, encoding="utf-8").read().splitlines()
    except Exception: continue
    for n, l in enumerate(lines, 1):
        for t in re.findall(r"[A-Za-z0-9+_-]{32,}", l):
            if re.fullmatch(r"[0-9a-f]{64}", t) or t.startswith("AAAAC3NzaC1lZDI1NTE5") or "<REDACTED_ONEDRIVE_FOLDER_ID>" in t: continue  # OneDrive folder id, not a credential
            if re.search(r"\d", t) and re.search(r"[A-Za-z]", t) and len(set(t)) > 12:
                print(f"{f}:{n}: {t[:6]}...({len(t)} chars)")
')
[[ -n "$ent" ]] && { echo "$ent" | sed 's/^/  high-entropy: /'; echo "FAIL: high-entropy string"; bad=1; }
# 3) informational: lines mentioning password/secret/token with a non-placeholder value
echo "$files" | xargs -d '\n' grep -nIEi '(password|secret|token)[a-z_]*\s*[:=]\s*[^ $"{(<]' 2>/dev/null \
  | grep -vEi "__REDACTED__|''|\"\"|: *(true|false|[0-9]+)$|^tools/|/messages/|mySQLColumn|Password: *password|verifyPw123" | cut -c1-160 | sed 's/^/  review: /'
((bad)) && { echo "SECRET SCAN: FAILED"; exit 1; } || echo "SECRET SCAN: clean"
