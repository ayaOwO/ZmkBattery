# ZmkBattery

A DankMaterialShell bar widget for the central and peripheral battery levels of
a ZMK split keyboard. It supports any number of peripherals connected to one
central.

The plugin finds a paired Bluetooth device by its configured name, discovers
its Battery Level characteristics through BlueZ, and distinguishes the central
value from ZMK's peripheral battery proxies using the standard GATT
Characteristic User Description descriptors.

## Requirements

- DankMaterialShell 1.5 or newer
- BlueZ
- `bash`
- `busctl`
- `jq`

## Setup

1. Open **Settings → Plugins** and scan for plugins.
2. Enable **ZmkBattery**.
3. Add **ZmkBattery** to the DankBar layout.
4. Open the plugin settings and set **Keyboard name** to the exact Bluetooth
   name or alias shown by `bluetoothctl devices`.

The default keyboard name is `Corne-ish Zen`. The widget refreshes every 60
seconds by default; clicking it refreshes immediately. It stays hidden while
the keyboard is disconnected and reappears after a successful refresh. The
settings page discovers every exposed battery and lets you rename each one
independently. Leave a label empty to show only that battery's percentage.

The settings page includes a copy button for this discovery command:

```bash
bluetoothctl devices
```

To expose both split battery levels, configure ZMK to fetch and proxy the
peripheral battery as described in the
[ZMK battery configuration guide](https://v0-3-branch.zmk.dev/docs/config/battery).

## Script usage

The underlying query can also be run directly:

```bash
./getBattery.sh "Corne-ish Zen"
```

You can alternatively set `ZMK_KEYBOARD_NAME`:

```bash
ZMK_KEYBOARD_NAME="Corne-ish Zen" ./getBattery.sh
```

The script writes a JSON array. Each battery has a stable ID, its GATT-derived
name, and either an integer percentage or `null` when that individual value
cannot be read.

Example output:

```json
[
  {"id":"central","name":"Central","level":79},
  {"id":"peripheral:0","name":"Peripheral 0","level":77},
  {"id":"peripheral:1","name":"Peripheral 1","level":null}
]
```

## Tests

Run the mocked BlueZ scenarios with:

```bash
./tests/getBattery_test.sh
```
