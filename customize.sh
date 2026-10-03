#!/system/bin/sh
# Magisk module installer hook (runs inside the Magisk installer).
SKIPUNZIP=0

CONF_DIR=/data/adb/socks5d
CONF=$CONF_DIR/config
KEY=$CONF_DIR/id_ed25519

ui_print "- Installing socks5d v1.1"

if [ "$ARCH" != "arm64" ]; then
  abort "! Unsupported architecture: $ARCH (arm64 only)"
fi

for f in socks5d dbclient dropbearkey service.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"

TUNNEL_BLOCK='
# --- SSH reverse tunnel (publishes this proxy on the SSH server) ---
# Set TUNNEL=1 and fill in TUN_HOST / TUN_USER, then reboot.
# The remote end listens on 127.0.0.1:TUN_REMOTE_PORT of the SSH server.
TUNNEL=0
TUN_HOST=
TUN_PORT=22
TUN_USER=
TUN_REMOTE_PORT=1080
# 1 = also log every successful CONNECT to socks5d.log
VERBOSE=0'

if [ ! -f "$CONF" ]; then
  # 122 bits of randomness from the kernel UUID generator
  PW=$(tr -d '-' < /proc/sys/kernel/random/uuid)
  cat > "$CONF" <<EOF
# socks5d config - edit, then reboot (or kill socks5d; the watchdog restarts it)
BIND=0.0.0.0
PORT=1080
USER=proxy
PASS=$PW
# DNS server used to resolve hostnames requested by clients
DNS=1.1.1.1:53
EOF
  printf '%s\n' "$TUNNEL_BLOCK" >> "$CONF"
  chmod 600 "$CONF"
  ui_print "- New config written to $CONF"
  ui_print "- Username: proxy"
  ui_print "- Password: $PW"
else
  ui_print "- Keeping existing config at $CONF"
  if ! grep -q '^TUNNEL=' "$CONF"; then
    printf '%s\n' "$TUNNEL_BLOCK" >> "$CONF"
    ui_print "- Added tunnel settings to the config"
  fi
fi

if [ ! -f "$KEY" ]; then
  if "$MODPATH/dropbearkey" -t ed25519 -f "$KEY" >/dev/null 2>&1; then
    chmod 600 "$KEY"
    ui_print "- Generated tunnel key: $KEY"
  else
    ui_print "! Could not generate the tunnel key. Later, as root, run:"
    ui_print "  /data/adb/modules/socks5d/dropbearkey -t ed25519 -f $KEY"
  fi
fi

if [ -f "$KEY" ]; then
  PUB=$("$MODPATH/dropbearkey" -y -f "$KEY" 2>/dev/null | grep '^ssh-')
  if [ -n "$PUB" ]; then
    ui_print "- Tunnel public key (add to authorized_keys on the SSH server):"
    ui_print "$PUB"
  fi
fi

ui_print "- Starts automatically on boot"
