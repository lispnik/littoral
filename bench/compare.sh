#!/bin/sh
# Measure one server: bench/compare.sh hunchentoot|woo|seaside [PORT]
# Prints one JSON object of results.  Needs ab (ApacheBench) and Node 22+.
# WORKERS sets Woo's event loops (4).  seaside runs the Pharo image that
# bench/seaside/setup.sh built in SEASIDE_DIR.
set -e
server=$1; port=${2:-8097}; node=${NODE:-node}
base=http://127.0.0.1:$port
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

if [ "$server" = seaside ]; then
  dir=${SEASIDE_DIR:?SEASIDE_DIR is the directory bench/seaside/setup.sh built}
  "$dir/pharo" "$dir/Pharo.image" eval --no-quit "LtStatsHandler startOn: $port" >/dev/null 2>&1 &
  static=/files/LtBenchFiles/littoral.js
else
  sbcl --non-interactive --load bench/load-server.lisp \
    --eval "(littoral-load:start-load-server :port $port :server :$server :workers ${WORKERS:-4} :max-threads 1000)" \
    --eval '(sleep 3600)' >/dev/null 2>&1 &
fi
for i in $(seq 1 120); do curl -s -o /dev/null $base/_stats && break; sleep 1; done
pid=$(lsof -nP -iTCP:$port -sTCP:LISTEN -t | head -1)
jar=$(mktemp)
trap 'kill -9 $pid 2>/dev/null; rm -f $jar' EXIT
rss() { ps -o rss= -p $pid | awk '{printf "%d", $1/1024}'; }
idle=$(rss)

ab_rps() { ab -q "$@" 2>/dev/null | awk '/Requests per second/ {printf "%d", $4}'; }
first=$(curl -s -L -c $jar -b $jar $base/counter)
if [ -z "$static" ]; then
  static=/littoral/files/$(echo "$first" | grep -o 'littoral.js?v=[0-9a-f]*')
fi
static_ka=$(ab_rps -k -n 50000 -c 64 "$base$static")
# The page a click on ++ ends at, rendered again and again.
link=$(echo "$first" | grep -o 'href="[^"]*">++<' | sed 's/href="//; s/">++<$//; s/&amp;/\&/g')
page=$(curl -s -L -c $jar -b $jar -o /dev/null -w '%{url_effective}' "$base$link" | sed "s|^$base||")
cookie=$(sed 's/^#HttpOnly_//' $jar | awk '!/^#/ && NF >= 7 {printf "%s=%s", $6, $7; exit}')
status=$(curl -s -o /dev/null -w '%{http_code}' ${cookie:+-b "$cookie"} "$base$page")
[ "$status" = 200 ] || { echo "$page answered $status, not 200" >&2; exit 1; }
render_ka=$(ab_rps -k -n 50000 -c 64 ${cookie:+-C "$cookie"} "$base$page")
render_new=$(ab_rps -n 20000 -c 32 ${cookie:+-C "$cookie"} "$base$page")

# Clicks from four clients at once, 16 users each.
clicks() {
  for c in 1 2 3 4; do
    CLICK_PATH=$1 CLICK_LINK="$2" USERS=16 SECONDS=10 BASE=$base $node bench/load.mjs click &
  done | grep -o '"perSecond": [0-9]*' | awk '{s+=$2} END {print s}'
}
latency() { grep -o "\"$1\": \"[0-9.]*\"" | grep -o '[0-9.]*"$' | tr -d '"'; }
counter=$(clicks /counter '\+\+')
store=$(clicks /store 'Add')
p99=$(CLICK_PATH=/counter USERS=64 SECONDS=10 BASE=$base $node bench/load.mjs click | latency p99)
one=$(CLICK_PATH=/counter USERS=1 SECONDS=10 BASE=$base $node bench/load.mjs click)
one_rate=$(echo "$one" | grep -o '"perSecond": [0-9]*' | grep -o '[0-9]*$')
one_p50=$(echo "$one" | latency p50)

memory=$(BASE=$base $node bench/load.mjs memory)
per_counter=$(echo "$memory" | awk '/memory_counter/ {f=1} f && /perSession/ {gsub(/[^0-9]/,""); print; exit}')
per_store=$(echo "$memory" | awk '/memory_store/ {f=1} f && /perSession/ {gsub(/[^0-9]/,""); print; exit}')

if [ "$server" = seaside ]; then
  streams=null                  # no push page to compare
else
  streams=$(SETTLE_MS=15000 SERVER_PID=$pid STREAMS=${STREAMS:-600} BASE=$base $node bench/load.mjs streams)
fi

printf '{"server":"%s","idle_rss_mb":%s,"static_keepalive_rps":%s,"render_keepalive_rps":%s,"render_new_connection_rps":%s,"counter_clicks_per_s":%s,"store_clicks_per_s":%s,"counter_p99_ms_64_users":%s,"one_user_clicks_per_s":%s,"one_user_p50_ms":%s,"bytes_per_counter_session":%s,"bytes_per_store_session":%s,"streams":%s}\n' \
  "$server" "$idle" "$static_ka" "$render_ka" "$render_new" "$counter" "$store" "$p99" "$one_rate" "$one_p50" "$per_counter" "$per_store" "$streams"
