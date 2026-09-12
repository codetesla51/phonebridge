#!/usr/bin/env bash
# phonebridge init — dependencies, pairing, config, relay APK, smoke test.
# Idempotent: safe to re-run any time.
set -u
cd "$(dirname "$0")"

PL=./phonebridge
CONF=~/.config/phonebridge/config.ini
PKG=dev.phonebridge.relay
APK=android-app/out/phonerelay.apk

say()  { printf '%s\n' "$*"; }
die()  { printf 'init: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have adb      || die "adb not found — install android-tools (pacman/apt: android-tools)"
have python3  || die "python3 not found"
[ -x "$PL" ]  || die "$PL not executable"
adb start-server >/dev/null 2>&1

# ── pair ────────────────────────────────────────────────────────────────
if ! adb devices 2>/dev/null | awk '$2=="device"{found=1} END{exit !found}'; then
    say "no device visible."
    say "first time (USB): plug in, then:  adb tcpip 5555   (unplug after)"
    printf 'phone address [host:port]: '
    read -r addr
    [ -n "${addr:-}" ] || die "no address given"
    adb connect "$addr" >/dev/null || die "cannot reach $addr"
    sleep 1
    adb devices 2>/dev/null | awk '$2=="device"{found=1} END{exit !found}' || die "connected but not authorized — accept the RSA prompt on the phone, re-run init"
    target="$addr"
else
    target="$(adb devices | awk '$2=="device"{print $1; exit}')"
    say "device: $target"
fi
dev="$target"

# ── config ──────────────────────────────────────────────────────────────
mkdir -p ~/.config/phonebridge
if [ ! -f "$CONF" ]; then
    printf 'friendly name for this device (blank = use model name): '
    read -r alias
    {
        echo "[phone]"
        echo "device = $dev"
        echo "target = $target"
        echo "remote_dir = /sdcard/Download"
        echo "inbox_dir = /sdcard/PhoneBridge"
        echo "downloads = ~/PhoneBridge"
        echo "shots = ~/Pictures/PhoneBridge"
        echo ""
        echo "[display]"
        [ -n "${alias:-}" ] && echo "alias_1 = = $alias"
        echo ""
        echo "[notify]"
        echo "# app_1 = com.whatsapp = WhatsApp"
    } > "$CONF"
    say "wrote $CONF"
else
    # refresh the remembered device/target, keep everything else
    python3 - "$CONF" "$dev" "$target" <<'EOF'
import configparser, sys
p, dev, tgt = sys.argv[1], sys.argv[2], sys.argv[3]
c = configparser.ConfigParser(); c.read(p)
if not c.has_section("phone"): c.add_section("phone")
c.set("phone", "device", dev); c.set("phone", "target", tgt)
with open(p, "w") as f: c.write(f)
EOF
    say "refreshed device in $CONF"
fi

# alias with empty substring would match everything — drop it
sed -i '/^alias_.*= *= *$/d' "$CONF"

# ── relay APK ───────────────────────────────────────────────────────────
if adb -s "$dev" shell pm path "$PKG" 2>/dev/null | grep -q "package:"; then
    say "relay app already installed ($PKG)"
else
    if [ -f "$APK" ]; then
        say "installing prebuilt relay app…"
    elif [ -d ~/Android/Sdk/build-tools ] && have javac; then
        say "building relay app…"
        (cd android-app && ./build.sh) || die "APK build failed (see android-app/README)"
    else
        die "relay app missing. Either: build it (JDK 17 + Android SDK build-tools + android-34, then android-app/build.sh), or install a prebuilt APK and re-run init"
    fi
    adb -s "$dev" install -r "$APK" | grep -q Success || die "adb install failed"
    say "relay app installed"
    sleep 3  # fresh installs need a beat before the first flash answers
fi
# share-sheet inbox (/sdcard/PhoneBridge) needs all-files access; needs the
# permission declared (it is) — if the ROM refuses the adb grant, flip it
# once in Settings > Special app access > All files access > PhoneBridge
if ! adb -s "$dev" shell appops get "$PKG" MANAGE_EXTERNAL_STORAGE 2>/dev/null | grep -q ": allow"; then
    adb -s "$dev" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1
fi
if adb -s "$dev" shell appops get "$PKG" MANAGE_EXTERNAL_STORAGE 2>/dev/null | grep -q ": allow"; then
    say "all-files access: granted"
else
    say "all-files access: NOT granted — sharing will fail until you allow it:"
    say "  Settings > Special app access > All files access > PhoneBridge > Allow"
fi

# ── smoke test ──────────────────────────────────────────────────────────
say "--- smoke test ---"
"$PL" devices
"$PL" battery
if "$PL" clip --text "phonebridge setup OK — paste me fast" >/dev/null; then
    say "clipboard push: OK (check the phone — paste immediately, this ROM reaps clips fast)"
else
    say "clipboard push: FAILED (share-sheet path still works; see README quirks)"
fi
say "---"
say "done. Add $(pwd) to PATH, then: phonebridge --help"
say "Build a UI on top: README 'Protocol for UI builders'."
