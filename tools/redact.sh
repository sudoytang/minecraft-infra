#!/usr/bin/env bash
# Replace secret values in tracked config with placeholders (idempotent).
set -euo pipefail
R=${1:-$(cd "$(dirname "$0")/.." && pwd)}
P="$R/server-config/files/server.properties"
sed -i -E 's/^(rcon\.password|management-server-secret|management-server-tls-keystore-password)=.+$/\1=__REDACTED__/' "$P"
G="$R/server-config/files/config/paper-global.yml"
# velocity forwarding secret
python3 - "$G" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(\n  velocity:\n(?:    .*\n)*?    secret: )(?!'')\S.*", r"\1__REDACTED__", s)
open(p, "w").write(s)
PY
A="$R/server-config/files/plugins/AuthMe/config.yml"
sed -i -E "s/^(\s*(mySQLPassword|mailPassword|emailOauth2Token|proxySharedSecret):) *(''|\"\")?$/&/; s/^(\s*(mySQLPassword|mailPassword|emailOauth2Token|proxySharedSecret):) +[^'\" ].*$/\1 __REDACTED__/; s/^(\s*(mySQLPassword|mailPassword|emailOauth2Token|proxySharedSecret):) +'[^']+'$/\1 __REDACTED__/" "$A"
