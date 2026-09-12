# phonebridge

<img src="assets/logo.png" alt="PhoneBridge logo" width="160">

PhoneBridge is a PC to Android bridge over adb: push files and clipboard
text to the phone, pull files back, read battery, ring a lost phone, and
forward its notifications to the desktop — with no account, no cloud, no
cable after the one-time Wi-Fi setup, and no app you ever have to open.
It is built in two halves so anyone can build their own interface on it:

- **Backend** (`phonebridge`, one stdlib-only Python file) — every phone
  operation as a small command that prints JSON. Scripts, bars, launchers,
  and full UIs all talk to the same CLI.
- **Relay app** (`android-app/`, ~200 lines, no Gradle) — an invisible
  flash target that sets the phone clipboard, plus a share-sheet target so
  anything shared from any phone app lands in `/sdcard/PhoneBridge/` for
  automatic pickup.
- **Reference client** (`clients/quickshell/`) — the author's own
  quickshell popup, kept thin on purpose so the backend stays honest.

## Quickstart

```bash
./init.sh        # deps, pairing, config, relay APK, smoke test
phonebridge --help # all commands
```

`init.sh` is idempotent — re-run it whenever the phone's address changes.
First-time Wi-Fi pairing needs one USB step (`adb tcpip 5555`), which it
walks you through.

## Commands

All commands print JSON to stdout. Errors go to stderr with a nonzero exit.

| command | does |
|---|---|
| `devices` | attached devices `[{id, name}]` (display aliases applied) |
| `connect [addr]` | `adb connect` (defaults to the remembered target) |
| `battery` | `{level, charging}` |
| `clip --text T \| --file F \| --stdin` | set the phone clipboard (`{status: ok\|empty\|toolong\|fail}`) |
| `push <local> [remote-dir]` | push a file + trigger the media scanner |
| `pull <name> [--dir D] [--dest DIR]` | pull a file (default dest `~/Downloads`) |
| `ls [remote-dir]` | `[{name, isDir}]`, dirs first |
| `shot [--dest DIR]` | screencap to PNG, prints the path |
| `ring` | wake + max volume + vibrate burst |
| `wake` | screen wake only |
| `inbox-sync [--dest DIR]` | pull new share-sheet files (`{pulled, skipped}`) |
| `inbox-watch [--interval N]` | `inbox-sync` loop, one JSON object per arrival |
| `notifs` | current notification records `[{key, label, title, sender, pkg}]` |
| `notifs-watch [--interval N]` | new records as JSON lines (first scan is absorbed, not emitted) |

Config lives at `~/.config/phonebridge/config.ini`: remembered device,
directories, `[display]` model-substring aliases, and the `[notify]`
pkg-substring allowlist for the notification watcher.

## Protocol for UI builders

One-shot state (`devices`, `battery`, `ls`, `notifs`, `inbox-sync`) is
plain request/response JSON. Live streams (`inbox-watch`, `notifs-watch`)
print one JSON object per line — tail the process and parse lines. `clip`
takes text on stdin, so clipboard managers stay compositor-specific on
your side (`wl-paste | phonebridge clip`, `xclip -o | phonebridge clip`).

`clients/` holds reference integrations (quickshell).

## Android app

`android-app/` builds the tiny relay APK (no Gradle: javac, d8, aapt2,
zipalign, apksigner — see its README). Two activities:

- **PhoneBridgeActivity** — invisible flash target for `clip`: sets the
  clipboard from an invisible window, writes `ack.txt`.
- **ShareRelayActivity** — share-sheet target (`text/plain` + `*/*`) that
  stores shared items in `/sdcard/PhoneBridge/`, which `inbox-sync`
  picks up. This is the robust phone-to-PC channel.

## Verified quirks

Found the hard way on an itel A663LC (Android 13); your ROM may differ:

- Shell-uid clipboard access is blocked (no `cmd clipboard`, binder
  `SecurityException`, silent rc-0 no-ops) — hence the flash-launch app.
- The relay app **cannot read foreign clips** (always empty, even with the
  `READ_CLIPBOARD` appop granted).
- Clips the relay **sets are reaped within seconds when idle** — `clip` is
  paste-now only. The share-sheet inbox has no such limit.
- `adb push` bypasses MediaStore — `push` fires the scanner broadcast per
  file so items show up in galleries promptly.
- Toybox `ls -l` on some ROMs omits the group column — parse by position
  accordingly (`inbox-sync` uses `stat`, not `ls -l`).

## License

MIT — see LICENSE.
