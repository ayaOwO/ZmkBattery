#!/usr/bin/env python3
"""Discover USB devices and read kernel batteries or a supported vendor protocol."""
import json
from pathlib import Path
import sys

from keychronProtocol import query_level


def read(path, default=''):
    try:
        return path.read_text().strip()
    except OSError:
        return default


def batteries(usb_root=Path('/sys/bus/usb/devices'),
              power_root=Path('/sys/class/power_supply'),
              hid_root=Path('/sys/class/hidraw')):
    result = []
    supplies = list(power_root.glob('*'))
    for device in sorted(usb_root.glob('*')):
        vendor, product = read(device / 'idVendor'), read(device / 'idProduct')
        if not vendor or not product or device.name.startswith('usb'):
            continue  # Interfaces and host root hubs are not peripherals.
        identity = read(device / 'serial') or device.name
        device_id = f'usb:{vendor}:{product}:{identity}'
        name = read(device / 'product') or f'USB {vendor}:{product}'
        entries = []
        for supply in supplies:
            if device.resolve() not in supply.resolve().parents:
                continue
            if read(supply / 'type') != 'Battery' or read(supply / 'present', '1') == '0':
                continue
            capacity = read(supply / 'capacity')
            level = int(capacity) if capacity.isdigit() and 0 <= int(capacity) <= 100 else None
            entries.append({
                'id': f'{device_id}:{read(supply / "model_name") or "battery"}',
                'name': read(supply / 'model_name') or name,
                'level': level,
            })
        # Only this supported receiver uses the Keychron mouse protocol.
        if not entries and (vendor, product) == ('3434', 'd028'):
            level = None
            for hid in hid_root.glob('*'):
                if device.resolve() not in (hid / 'device').resolve().parents:
                    continue
                if '/input4\n' not in read(hid / 'device/uevent') + '\n':
                    continue
                try:
                    level = query_level(f'/dev/{hid.name}')
                except OSError as error:
                    print(f'{name}: {error}', file=sys.stderr)
                break
            entries = [{'id': device_id, 'name': name, 'level': level}]
        for entry in entries:
            entry.update(supported=True)
        result.extend(entries)
    return result


if __name__ == '__main__':
    print(json.dumps(batteries()))
