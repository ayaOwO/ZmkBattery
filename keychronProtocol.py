#!/usr/bin/env python3
"""Query Ultra-Link 8K battery status without third-party dependencies.

Protocol: https://github.com/csutcliff/keychron-battery-dkms
"""
import fcntl
import os
import select
import time


def query_level(device):
    fd = os.open(device, os.O_RDWR | os.O_NONBLOCK)
    try:
        for _ in range(3):
            request = bytearray(64)
            request[:2] = b'\xb3\x06'
            fcntl.ioctl(fd, 0xC0404806, request)  # HIDIOCSFEATURE(64)
            deadline = time.monotonic() + 0.5
            while (remaining := deadline - time.monotonic()) > 0:
                if not select.select([fd], [], [], remaining)[0]:
                    break
                data = os.read(fd, 64)
                if len(data) > 20 and data[:2] == b'\xb4\x06' and data[20] <= 100:
                    return data[20]
        return None
    finally:
        os.close(fd)
