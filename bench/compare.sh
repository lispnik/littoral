#!/bin/sh
# Measure one server: bench/compare.sh hunchentoot|woo [PORT]
# Prints one JSON object of results.  Needs ab (ApacheBench) and Node 22+.
set -e
server=$1; port=${2:-8097}; node=${NODE:-node}
base=http://127.0.0.1:$port
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

sbcl --non-interactive --load bench/load-server.lisp \
  --eval "(littoral-load:start-load-server :port $port :server :$server :workers 4 :max-threads 1000)" \
  --eval '(sleep 3600)' >/dev/null 2>&1 &
for i in $(seq 1 120); do curl -s -o /dev/null $base/_stats && break; sleep 1; done
pid=$(lsof -nP -iTCP:$port -sTCP:LISTEN -t | head -1)
trap 'kill -9 $pid 2>/dev/null' EXIT
rss() { ps -o rss= -p $pid | awk '{printf "%d", $1/1024}'; }
idle=$(rss)

ab_rps() { ab -q "$@" 2>/dev/null | awk '/Requests per second/ {printf "%d", $4}'; }
js=$(curl -s -L $base/counter | grep -o 'littoral.js?v=[0-9a-f]*')
static_ka=$(ab_rps -k -n 50000 -c 64 "$base/littoral/files/$js")
head=$(curl -s -D - -o /dev/null $base/counter)
page=$(echo "$head" | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r')
cookie=$(echo "$head" | awk 'tolower($1)=="set-cookie:" {print $2}' | sed 's/;.*//' | tr -d '\r')
render_ka=$(ab_rps -k -n 50000 -c 64 -C "$cookie" "$base$page")
render_new=$(ab_rps -n 20000 -c 32 -C "$cookie" "$base$page")

# Clicks from four clients at once, 16 users each.
clicks() {
  for c in 1 2 3 4; do
    CLICK_PATH=$1 CLICK_LINK="$2" USERS=16 SECONDS=10 BASE=$base $node bench/load.mjs click &
  done | grep -o '"perSecond": [0-9]*' | awk '{s+=$2} END {print s}'
}
counter=$(clicks /counter '\+\+')
store=$(clicks /store 'Add')
p99=$(CLICK_PATH=/counter USERS=64 SECONDS=10 BASE=$base $node bench/load.mjs click | grep -o '"p99": "[0-9.]*"' | grep -o '[0-9.]*"$' | tr -d '"')

memory=$(BASE=$base $node bench/load.mjs memory)
per_counter=$(echo "$memory" | awk '/memory_counter/ {f=1} f && /perSession/ {gsub(/[^0-9]/,""); print; exit}')
per_store=$(echo "$memory" | awk '/memory_store/ {f=1} f && /perSession/ {gsub(/[^0-9]/,""); print; exit}')

streams=$(SETTLE_MS=15000 SERVER_PID=$pid STREAMS=${STREAMS:-600} BASE=$base $node bench/load.mjs streams)

printf '{"server":"%s","idle_rss_mb":%s,"static_keepalive_rps":%s,"render_keepalive_rps":%s,"render_new_connection_rps":%s,"counter_clicks_per_s":%s,"store_clicks_per_s":%s,"counter_p99_ms_64_users":%s,"bytes_per_counter_session":%s,"bytes_per_store_session":%s,"streams":%s}\n' \
  "$server" "$idle" "$static_ka" "$render_ka" "$render_new" "$counter" "$store" "$p99" "$per_counter" "$per_store" "$streams"
