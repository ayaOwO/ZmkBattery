# ZmkBattery

A DankMaterialShell bar widget for the central and peripheral battery levels of
all connected ZMK keyboards and supported USB devices. It supports any number
of keyboards and their peripherals, Linux-reported USB batteries, and automatic Keychron Ultra-Link 8K battery reporting.

The plugin discovers connected Bluetooth Battery Level characteristics through
BlueZ, including ZMK peripheral battery proxies. Devices such as Bluetooth
headsets can also report through BlueZ Battery1 without a GATT service.
USB batteries are read through
Linux power_supply. Only USB devices with a battery service or supported
vendor reader appear. A USB ID alone does not provide battery support for
other proprietary protocols.

## Requirements

- DankMaterialShell 1.5 or newer
- BlueZ
- `bash`
- `busctl`
- `jq`
- `python3` for optional USB battery support; the Keychron reader also needs
  user read/write access to the receiver’s `/dev/hidraw*` device

## Setup

1. Open **Settings → Plugins** and scan for plugins.
2. Enable **ZmkBattery**.
3. Add **ZmkBattery** to the DankBar layout.
4. Open plugin settings to see the discovered battery list. Turn off **Show in
   widget** for unwanted batteries and edit their labels.
5. Supported Keychron Ultra-Link 8K receivers automatically use the Keychron
   battery reader. Other USB devices use Linux battery services when available.
   Devices without battery support are omitted from settings and the bar.
   No reader selection is required.

Discovery is automatic. The widget refreshes every 60 seconds by default;
clicking it refreshes immediately. Hidden batteries remain in the settings list
so they can be shown again. Drag the grip beside each battery to choose its order in the bar
(or focus the grip and use the up/down keys); the order is saved by battery ID. New batteries
appear after those you have ordered. Leave a label empty to show only its percentage.
The Display settings let you choose the separator between horizontal bar readings
and pick the widget icon. An empty separator hides it.
Bluetooth batteries use address-based IDs. USB batteries use vendor/product ID
plus serial number where available, otherwise the USB port path. Names are
only display labels. Existing keyboard labels are retained through the legacy
keyboard name setting; the optional script argument now identifies that legacy
keyboard rather than filtering discovery.

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

The script writes a JSON array. Each battery has a stable ID, its device
name, and either an integer percentage or `null` when that individual value
cannot be read.

Example output:

```json
[
  {"id":"bluetooth:aa:bb:cc:dd:ee:ff:central","name":"Central","level":79},
  {"id":"bluetooth:aa:bb:cc:dd:ee:ff:peripheral:0","name":"Peripheral 0","level":77},
  {"id":"bluetooth:aa:bb:cc:dd:ee:ff:peripheral:1","name":"Peripheral 1","level":null},
  {"id":"usb:vendor:product:serial","name":"USB mouse","level":96}
]
```

## Tests

Run the mocked Bluetooth, settings, and USB checks with:

```bash
./tests/getBattery_test.sh
./tests/settings_test.sh
python3 -B tests/usb_test.py
```

Use **Hide % symbol** to keep numeric battery levels visible without the percent sign. The **Test low battery notification** button
sends a sample desktop notification; it does not change any battery readings.
