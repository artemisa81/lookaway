#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 artemisa81

"""Regression tests for the dependency-free AirPods sensor helper."""

import importlib.util
import socket
import subprocess
import sys
import unittest
from pathlib import Path
from importlib.machinery import SourceFileLoader
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "bin" / "lookaway-sensor"
LOADER = SourceFileLoader("lookaway_sensor", str(MODULE_PATH))
SPEC = importlib.util.spec_from_loader("lookaway_sensor", LOADER)
sensor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sensor)


def head_packet(values=(100, 200, 300)):
    packet = bytearray(sensor.HT_MIN)
    packet[:10] = sensor.HT_PREFIX
    packet[10] = 0x44
    packet[11] = 0
    for offset, value in zip((sensor.OFF_O1, sensor.OFF_O2, sensor.OFF_O3), values):
        packet[offset:offset + 2] = value.to_bytes(2, "little", signed=True)
    return bytes(packet)


class FakeSocket:
    def __init__(self, packets):
        self.packets = iter(packets)
        self.sent = []
        self.closed = False

    def sendall(self, packet):
        self.sent.append(packet)

    def send(self, packet):
        self.sendall(packet)

    def recv(self, _size):
        packet = next(self.packets)
        if packet is socket.timeout:
            raise socket.timeout()
        return packet

    def close(self):
        self.closed = True


class SensorTests(unittest.TestCase):
    def test_l2cap_eof_closes_stream_and_reconnects_at_outer_layer(self):
        fake = FakeSocket([b""])
        with mock.patch.object(sensor, "open_l2cap", return_value=fake), \
             mock.patch.object(sensor, "handshake"):
            with self.assertRaisesRegex(ConnectionError, "channel closed"):
                sensor.stream("00:11:22:33:44:55", "alt", False)
        self.assertTrue(fake.closed)

    def test_auto_fallback_happens_with_continuous_non_sensor_notifications(self):
        fake = FakeSocket([b"notification"] * 8)
        clock = iter((0, 2, 4, 6, 8, 10, 12))
        with mock.patch.object(sensor.time, "monotonic", side_effect=clock):
            with self.assertRaisesRegex(ConnectionError, "did not start"):
                sensor.pump(fake, [("ALT", b"alt"), ("DEF", b"def")], False)
        self.assertEqual(fake.sent, [b"alt", b"def"])

    def test_stalled_established_stream_is_not_left_alive(self):
        fake = FakeSocket([head_packet()] * sensor.CALIB_N + [socket.timeout])
        times = [0] + [index / 10 for index in range(1, sensor.CALIB_N + 1)] + [9]
        with mock.patch.object(sensor.time, "monotonic", side_effect=iter(times)):
            with self.assertRaisesRegex(ConnectionError, "stream stalled"):
                sensor.pump(fake, [("ALT", b"alt")], False)

    def test_moving_calibration_is_rejected_until_still(self):
        calibrator = sensor.Calibrator()
        for index in range(sensor.CALIB_N):
            self.assertIsNone(calibrator.feed(index * 1000, 0, 0))
        neutral = None
        for _ in range(sensor.CALIB_N):
            neutral = calibrator.feed(100, 200, 300)
        self.assertEqual(neutral, (100, 200, 300))

    def test_unknown_ear_state_is_ignored(self):
        self.assertIsNone(sensor.decode_ear(sensor.EAR_PREFIX + bytes([3, 3])))
        self.assertEqual(sensor.decode_ear(sensor.EAR_PREFIX + bytes([0, 1])), (0, 1))

    def test_discovery_returns_all_airpods_candidates(self):
        result = subprocess.CompletedProcess([], 0,
            "Device 00:00:00:00:00:01 Jose’s AirPods\n"
            "Device 00:00:00:00:00:02 Office AirPods\n")
        with mock.patch.object(sensor.subprocess, "run", return_value=result):
            self.assertEqual(sensor.find_airpods(), [
                "00:00:00:00:00:01",
                "00:00:00:00:00:02",
            ])

    def test_selftest_is_not_disabled_with_python_optimized_mode(self):
        result = subprocess.run(
            [sys.executable, "-O", str(MODULE_PATH), "--selftest"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("selftest OK", result.stdout)

    def test_invalid_demo_period_is_rejected(self):
        result = subprocess.run(
            [sys.executable, str(MODULE_PATH), "--demo", "--period", "0"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("finite positive", result.stderr)


if __name__ == "__main__":
    unittest.main()
