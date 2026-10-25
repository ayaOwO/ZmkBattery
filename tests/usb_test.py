#!/usr/bin/env python3
"""Exercise response validation, timeout, and descriptor cleanup without hardware."""
import importlib.util
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('keychron', Path(__file__).resolve().parents[1] / 'keychronProtocol.py')
keychron = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keychron)

response = bytearray(64)
response[:2] = b'\xb4\x06'
response[20] = 96

with patch.object(keychron.os, 'open', return_value=7), \
     patch.object(keychron.os, 'close') as close, \
     patch.object(keychron.fcntl, 'ioctl') as ioctl, \
     patch.object(keychron.select, 'select', return_value=([7], [], [])), \
     patch.object(keychron.os, 'read', side_effect=[b'\xb4', b'\xb4\x05' + bytes(62), bytes(response)]):
    assert keychron.query_level('/dev/test') == 96
    assert ioctl.call_args.args[2][:2] == b'\xb3\x06'
    close.assert_called_once_with(7)

response[20] = 101
with patch.object(keychron.os, 'open', return_value=7), \
     patch.object(keychron.os, 'close') as close, \
     patch.object(keychron.fcntl, 'ioctl'), \
     patch.object(keychron.select, 'select', side_effect=[([7], [], []), ([], [], []), ([], [], []), ([], [], [])]), \
     patch.object(keychron.os, 'read', return_value=bytes(response)):
    assert keychron.query_level('/dev/test') is None
    close.assert_called_once_with(7)

print('Keychron tests passed')

# List only USB battery sources and use the vendor reader only for a supported receiver.
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import getUsbBatteries as usb

with tempfile.TemporaryDirectory() as directory, patch.object(usb, 'query_level', return_value=87) as query:
    root = Path(directory)
    device = root / 'devices' / '1-5'
    device.mkdir(parents=True)
    for name, value in {'idVendor': '1234', 'idProduct': 'abcd', 'serial': 'serial-1', 'product': 'Test Mouse'}.items():
        (device / name).write_text(value)
    usb_root = root / 'usb'
    usb_root.mkdir()
    (usb_root / '1-5').symlink_to(device)
    supplies = root / 'power'
    supplies.mkdir()
    hid_root = root / 'hidraw'
    hid_device = device / 'interface4' / 'hid'
    hid_device.mkdir(parents=True)
    (hid_device / 'uevent').write_text('HID_PHYS=usb-test/input4\n')
    (hid_root / 'hidraw9').mkdir(parents=True)
    (hid_root / 'hidraw9' / 'device').symlink_to(hid_device)
    options = dict(usb_root=usb_root, power_root=supplies, hid_root=hid_root)
    device_id = 'usb:1234:abcd:serial-1'
    entries = usb.batteries(**options)
    assert entries == []
    query.assert_not_called()
    (device / 'idVendor').write_text('3434')
    (device / 'idProduct').write_text('d028')
    selected = usb.batteries(**options)
    assert selected[0]['level'] == 87 and selected[0]['supported'] is True
    query.assert_called_once_with('/dev/hidraw9')
    query.reset_mock()
    # A different Keychron device must not receive this mouse protocol.
    (device / 'idProduct').write_text('0001')
    assert usb.batteries(**options) == []
    query.assert_not_called()
    (device / 'idProduct').write_text('d028')
    supply = device / 'power_supply' / 'battery'
    supply.mkdir(parents=True)
    (supplies / 'battery').symlink_to(supply)
    (supply / 'type').write_text('Battery')
    (supply / 'capacity').write_text('42')
    assert usb.batteries(**options)[0]['level'] == 42
    (supply / 'capacity').write_text('101')
    assert usb.batteries(**options)[0]['level'] is None
    (supply / 'present').write_text('0')
    (device / 'idVendor').write_text('1234')
    assert usb.batteries(**options) == []
    query.assert_not_called()

print('USB discovery and automatic reader tests passed')
