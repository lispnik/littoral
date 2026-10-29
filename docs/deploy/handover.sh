#!/bin/sh
# handover.sh APP EXECUTABLE — deploy EXECUTABLE as APP without losing
# sessions.  APP runs as the systemd units APP@a and APP@b (app@.service),
# on ports 8081 and 8082, behind a proxy that routes by session key
# (nginx-handover.conf or Caddyfile.handover).  The new version starts as
# whichever instance isn't running; once its /healthz answers, the old one
# is told to drain: it serves its sessions until they end, then exits.
set -eu

app=${1:?usage: handover.sh APP EXECUTABLE}
executable=${2:?usage: handover.sh APP EXECUTABLE}
dir=${APP_DIR:-/opt/$app}

port_of() { case $1 in a) echo 8081 ;; b) echo 8082 ;; esac; }

if systemctl is-active --quiet "$app@a"; then old=a; new=b
elif systemctl is-active --quiet "$app@b"; then old=b; new=a
else old=; new=a
fi

# Renamed into place: the old instance keeps running the file it started from.
install -m 755 "$executable" "$dir/.$app.new"
mv -f "$dir/.$app.new" "$dir/$app"

systemctl start "$app@$new"
port=$(port_of "$new")
tries=0
until curl -fsS -o /dev/null "http://127.0.0.1:$port/healthz"; do
    tries=$((tries + 1))
    if [ "$tries" -ge 60 ]; then
        echo "$app@$new didn't become healthy; stopping it.  $app@${old:-?} goes on serving." >&2
        systemctl stop "$app@$new"
        exit 1
    fi
    sleep 1
done
systemctl enable --quiet "$app@$new"
echo "$app@$new is serving on $port."

if [ -n "$old" ]; then
    systemctl disable --quiet "$app@$old"
    systemctl kill -s USR1 "$app@$old"
    echo "$app@$old is draining; it exits once its sessions end (journalctl -fu $app@$old)."
fi
