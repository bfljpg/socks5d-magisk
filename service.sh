#!/system/bin/sh
MODDIR=${0%/*}
DIR=/data/adb/socks5d
CONF=$DIR/config
KEY=$DIR/id_ed25519
WLOG=$DIR/watchdog.log
TLOG=$DIR/tunnel.log

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 10

[ -f "$CONF" ] || exit 1

# dbclient keeps known_hosts in $HOME/.ssh
export HOME=$DIR
mkdir -p "$DIR/.ssh"

# trim FILE: keep the last 64 KB once it passes 256 KB
trim() {
  if [ -f "$1" ] && [ "$(wc -c < "$1")" -gt 262144 ]; then
    tail -c 65536 "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  fi
}

wlog() {
  trim "$WLOG"
  echo "$(date '+%F %T') $*" >> "$WLOG"
}

# SOCKS5 server watchdog. socks5d writes its own rotated log (socks5d.log).
(
  while true; do
    . "$CONF"
    V=""
    [ "$VERBOSE" = "1" ] && V="-v"
    wlog "starting socks5d on ${BIND:-0.0.0.0}:${PORT:-1080}"
    "$MODDIR/socks5d" -l "${BIND:-0.0.0.0}:${PORT:-1080}" -u "$USER" -p "$PASS" \
      -dns "${DNS:-1.1.1.1:53}" -log "$DIR/socks5d.log" $V >/dev/null 2>&1
    RC=$?
    wlog "socks5d exited ($RC), restarting in 5s"
    sleep 5
  done
) &

# Reverse tunnel watchdog (only when TUNNEL=1 and host/user are set).
(
  while true; do
    . "$CONF"
    if [ "$TUNNEL" = "1" ] && [ -n "$TUN_HOST" ] && [ -n "$TUN_USER" ]; then
      trim "$TLOG"
      wlog "starting tunnel to $TUN_USER@$TUN_HOST:${TUN_PORT:-22} (remote 127.0.0.1:${TUN_REMOTE_PORT:-1080})"
      "$MODDIR/dbclient" -N -T -y -i "$KEY" -p "${TUN_PORT:-22}" -K 30 -I 0 \
        -o ExitOnForwardFailure=yes -o BatchMode=yes \
        -R "127.0.0.1:${TUN_REMOTE_PORT:-1080}:127.0.0.1:${PORT:-1080}" \
        "$TUN_USER@$TUN_HOST" >> "$TLOG" 2>&1
      RC=$?
      wlog "tunnel exited ($RC), retrying in 10s"
      sleep 10
    else
      sleep 30
    fi
  done
) &
