#!/usr/bin/env bash
# Restore verification for the Paper server weekly backup.
# Usage: run.sh [ARCHIVE.tar.gz]
#   - With no arg: uses ONEDRIVE_URL (a pre-authenticated Graph downloadUrl) if set,
#     else the newest *.tar.gz already in work/.
#   - ARCHIVE_NAME env overrides the recorded archive name.
# Never touches the live server.
set -uo pipefail
BASE=/workspace/mc-restore-verify
WORK=$BASE/work; OPT=$BASE/opt; SRV=$WORK/server
SEED=__REDACTED__
PAPER_JAR=$OPT/paper-26.2-123.jar
PAPER_SHA=7b7b3b43c009103e1971a0576c26f655a7dd9b56a0a2a4438e352c03a7fecd08
JAVA=$(ls -d $OPT/jdk-25*/bin/java | head -1)
BOT=$OPT/verify_bot
RESULT=$BASE/last-result.txt
LOG=$BASE/last-run.log
exec > >(tee "$LOG") 2>&1
T0=$(date +%s)
declare -A ST TM; ORDER=(download integrity structure boot client stop cleanup)
for s in "${ORDER[@]}"; do ST[$s]=SKIP; TM[$s]=0; done
NOTES=()
JPID=""; BPID=""; MPID=""
log(){ echo "[$(date '+%F %T')] $*"; }
step(){ CUR=$1; TS=$(date +%s); log "== $1"; }
done_step(){ ST[$CUR]=$1; TM[$CUR]=$(( $(date +%s) - TS )); log "== $CUR: $1 (${TM[$CUR]}s)"; [ -n "${2:-}" ] && NOTES+=("$CUR: $2"); }
peak_file=$WORK/.peak
write_result(){
  printf '%s\n' "${NOTES[@]:-}" > $WORK/.notes
  PEAK=$(cat $peak_file 2>/dev/null || echo 0)
  overall=PASS; for s in "${ORDER[@]}"; do [ "${ST[$s]}" = FAIL ] && overall=FAIL; done
  python3 - "$RESULT" <<PY
import json,sys
d={"overall":"$overall","archive":"${ARCHIVE_NAME:-}","archive_bytes":${SIZE:-0},
   "started":"$(date -d @$T0 '+%F %T %Z')","total_seconds":$(( $(date +%s)-T0 )),
   "peak_rss_mb":$PEAK,
   "steps":{$(for s in "${ORDER[@]}"; do printf '"%s":{"status":"%s","seconds":%s},' $s ${ST[$s]} ${TM[$s]}; done | sed 's/,$//')},
   "notes":[l.rstrip() for l in open("$WORK/.notes") if l.strip()]}
open(sys.argv[1],"w").write(json.dumps(d,indent=2,ensure_ascii=False)+"\n"); print(json.dumps(d,indent=2,ensure_ascii=False))
PY
}
cleanup(){
  [ -n "$BPID" ] && kill $BPID 2>/dev/null
  if [ -n "$JPID" ] && kill -0 $JPID 2>/dev/null; then
    python3 $BASE/rcon.py $RPORT $RPW stop >/dev/null 2>&1; for i in $(seq 60); do kill -0 $JPID 2>/dev/null || break; sleep 1; done
    kill -9 $JPID 2>/dev/null
  fi
  [ -n "$MPID" ] && kill $MPID 2>/dev/null
}
abort(){ cleanup; rm -rf "$SRV"; ST[cleanup]=PASS; write_result; exit 1; }
trap 'NOTES+=("interrupted"); abort' INT TERM

# memory sampler: peak RSS (MB) of java + bot
( pk=0; while true; do r=0; for p in $(pgrep -f "$OPT/jdk-25.*paper.jar|$BOT"); do v=$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null); r=$((r+${v:-0})); done
  [ $r -gt $pk ] && pk=$r && echo $((pk/1024)) > $peak_file; sleep 2; done ) & MPID=$!

# 1. download
step download
ARCHIVE=${1:-}
if [ -z "$ARCHIVE" ] && [ -n "${ONEDRIVE_URL:-}" ]; then
  rm -rf "$WORK"/*.tar.gz "$SRV"; ARCHIVE=$WORK/${ARCHIVE_NAME:-weekly.tar.gz}
  curl -fsSL -o "$ARCHIVE" "$ONEDRIVE_URL" && done_step PASS || { done_step FAIL "curl failed"; abort; }
else
  [ -z "$ARCHIVE" ] && ARCHIVE=$(ls -t $WORK/*.tar.gz 2>/dev/null | head -1)
  [ -f "$ARCHIVE" ] && done_step PASS "pre-downloaded by agent" || { done_step FAIL "no archive"; abort; }
fi
ARCHIVE_NAME=${ARCHIVE_NAME:-$(basename "$ARCHIVE")}
SIZE=$(stat -c %s "$ARCHIVE"); log "archive $ARCHIVE_NAME $SIZE bytes"
[ -n "${EXPECT_SIZE:-}" ] && [ "$EXPECT_SIZE" != "$SIZE" ] && NOTES+=("size mismatch vs OneDrive $EXPECT_SIZE")

# 2. integrity
step integrity
if gzip -t "$ARCHIVE" && tar -tzf "$ARCHIVE" >/dev/null && { [ -z "${EXPECT_SIZE:-}" ] || [ "$EXPECT_SIZE" = "$SIZE" ]; }; then done_step PASS; else done_step FAIL; abort; fi

# 3. structure
step structure
rm -rf "$SRV"; mkdir -p "$SRV"
tar -xzf "$ARCHIVE" -C "$SRV" || { done_step FAIL "extract failed"; abort; }
SJSON=$(python3 $BASE/check_structure.py "$SRV" $SEED); rc=$?; log "$SJSON"
[ $rc = 0 ] && done_step PASS "$SJSON" || { done_step FAIL "$SJSON"; abort; }

# 4. boot
step boot
echo "$PAPER_SHA  $PAPER_JAR" | sha256sum -c --quiet || { done_step FAIL "paper jar checksum"; abort; }
freeport(){ python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
GPORT=$(freeport); RPORT=$(freeport); RPW=$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')
P=$SRV/server.properties
setp(){ if grep -q "^$1=" $P; then sed -i "s|^$1=.*|$1=$2|" $P; else echo "$1=$2" >> $P; fi; }
setp server-port $GPORT; setp query.port $GPORT; setp server-ip 127.0.0.1; setp online-mode false
setp enable-rcon true; setp rcon.ip 127.0.0.1; setp rcon.port $RPORT; setp rcon.password $RPW
setp white-list false; setp enforce-whitelist false; setp enable-query false; setp management-server-port 0
setp view-distance 4; setp simulation-distance 4
# plugins kept as in archive; bStats telemetry off
[ -f $SRV/plugins/bStats/config.yml ] && sed -i 's/enabled: true/enabled: false/' $SRV/plugins/bStats/config.yml
rm -f $SRV/world/session.lock
cp $PAPER_JAR $SRV/paper.jar
# reuse cached mojang jar/libraries between runs (archive excludes them)
mkdir -p $OPT/cache/{cache,libraries,versions}; for d in cache libraries versions; do rm -rf $SRV/$d; ln -s $OPT/cache/$d $SRV/$d; done
log "test server port $GPORT rcon $RPORT"
( cd $SRV && exec "$JAVA" -Xms256M -Xmx1G -XX:+UseSerialGC -jar paper.jar --nogui < /dev/null > $SRV/console.log 2>&1 ) & JPID=$!
ok=0; for i in $(seq 600); do
  grep -q 'Done (' $SRV/console.log 2>/dev/null && { ok=1; break; }
  kill -0 $JPID 2>/dev/null || break; sleep 1; done
SL=$SRV/logs/latest.log
CHUNK_ERR='(ERROR|WARN).*(chunk|region|Chunk|Region|corrupt|Corrupt)|Failed to (read|load) chunk|Exception.*(chunk|region|nbt)'
if [ $ok = 1 ] && ! grep -Eq "$CHUNK_ERR" $SL; then done_step PASS "$(grep -o 'Done ([^)]*)' $SL)"; else done_step FAIL "$( [ $ok = 1 ] || echo 'no Done;') $(grep -E "$CHUNK_ERR" $SL | head -3)"; abort; fi
rc(){ python3 $BASE/rcon.py $RPORT $RPW "$@"; }

# 5. client
step client
BOTLOG=$WORK/bot.log
VERIFY_SERVER=127.0.0.1:$GPORT VERIFY_USER=verify_bot VERIFY_PASSWORD=$(head -c9 /dev/urandom | od -An -tx1 | tr -d ' \n') VERIFY_SECONDS=150 \
  $BOT > $BOTLOG 2>&1 & BPID=$!
for i in $(seq 60); do grep -q SPAWNED $BOTLOG && break; sleep 1; done
cfail=""
grep -q SPAWNED $BOTLOG || cfail="no spawn;"
sleep 8
rc "op verify_bot" "gamemode creative verify_bot" >/dev/null   # creative: no fall/mob deaths confounding the tp checks
SPAWN=$(python3 - "$SRV/world/level.dat" <<'PY'
import gzip,sys
exec(open('/workspace/mc-restore-verify/check_structure.py').read().split('def find_key')[0])
d=nbt(gzip.open(sys.argv[1]).read())['Data']; s=d.get('spawn',{}); p=s.get('pos') or [d.get('SpawnX',0),d.get('SpawnY',64),d.get('SpawnZ',0)]
print(s.get('dimension','minecraft:overworld'), p[0]+0.5, p[1], p[2]+0.5)
PY
)
read SDIM SX SY SZ <<<"$SPAWN"
for tgt in "minecraft:overworld -206.5 48.9 -253.5" "minecraft:the_nether 183.5 256 55.5" "$SDIM $SX $SY $SZ"; do
  read dim x y z <<<"$tgt"
  out=$(rc "execute in $dim run tp verify_bot $x $y $z"); log "tp $tgt -> $out"
  below=$(rc "execute in $dim if block ${x%.*} $(( ${y%.*} - 1 )) ${z%.*} minecraft:air"); log "block below target: ${below:-not air}"
  sleep 15
  got=$(rc "data get entity verify_bot Dimension" "data get entity verify_bot Pos"); log "$got"
  echo "$got" | grep -q "$dim" || cfail="$cfail tp $dim not confirmed;"
  kill -0 $BPID 2>/dev/null || cfail="$cfail bot exited;"
done
grep -q DISCONNECT $BOTLOG && cfail="$cfail disconnected: $(grep DISCONNECT $BOTLOG | head -1);"
grep -Eq "$CHUNK_ERR" $SL && cfail="$cfail chunk errors during client: $(grep -E "$CHUNK_ERR" $SL | head -2);"
AUTH=$(grep -ciE 'CHAT.*(success|logged|registered)' $BOTLOG)
[ "$AUTH" -ge 1 ] || cfail="$cfail authme login not confirmed;"
kill $BPID 2>/dev/null; BPID=""
[ -z "$cfail" ] && done_step PASS "spawned, authme ok, tp overworld/nether/spawn($SDIM $SX $SY $SZ) confirmed" || done_step FAIL "$cfail"

# 6. stop + cleanup
step stop
rc stop >/dev/null 2>&1; for i in $(seq 90); do kill -0 $JPID 2>/dev/null || break; sleep 1; done
if kill -0 $JPID 2>/dev/null; then kill -9 $JPID; done_step FAIL "had to kill"; else done_step PASS; fi; JPID=""
cp $SL $BASE/last-server.log 2>/dev/null; cp $BOTLOG $BASE/last-bot.log 2>/dev/null
kill $MPID 2>/dev/null; MPID=""
step cleanup
rm -rf "$SRV" "$BOTLOG"; [ "${KEEP_ARCHIVE:-0}" = 1 ] || rm -f "$ARCHIVE"; done_step PASS
write_result
[ "$(python3 -c "import json;print(json.load(open('$RESULT'))['overall'])")" = PASS ]
