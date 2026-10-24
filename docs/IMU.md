# IMU200 interface used by this project

All probes are unicast. ID200 is a read-only sensor, never a motor-write target.
Link: Feetech SCS/STS framing, 1 Mbps, 8N1, half-duplex TTL.

## IMU-to-Feetech v0.1

Identity at 0/5: `00 01 00 49 46`.

Read 124/20; 56/20 is the same data alias. Offsets below are relative to the block.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0–5 | 3 × int16 LE | Gyro XYZ, raw × 0.0175 degrees/s |
| 6–11 | 3 × IEEE binary16 LE | Quaternion XYZ; recover W >= 0 and normalize |
| 12–17 | 3 × int16 LE | Accel XYZ, raw × 0.000122 g |
| 18 | u8 | Quaternion sample counter, wraps 255 → 0 |
| 19 | u8 | Flags |

Flags: bit0 initialized; bit1 gyro valid; bit2 quaternion valid; bit3 stale;
bit4 FIFO overrun; bit5 I/O error; bit6 READY; bit7 accel valid. Normal: C7.
Reject stale/error flags and absent validity bits. Reject non-finite or invalid
quaternions. A ready unit quaternion XYZ=0 is legitimate.

The firmware's stale threshold is 100 ms. The host uses an additional combined
bus-cycle budget of 20 ms, a conservative 120 ms limit, and repeated-counter
checks. This is not FT6's 30 ms freshness guarantee and is not an exact age.
After the fifteen-servo 56/15 Sync Read, the host performs a separate IMU unicast
124/20 read. This avoids assumptions about mixed-device response order.

## kissqy FT6

Identity at 0/5: `06 00 00 00 F2`. Original 56/15 fast layout, readiness,
diagnostic schema and freshness checks are retained. Do not interpret v0.1 accel
bytes as FT6 sequence/status/reserved fields.

The similarly named community PDF v1.2 is a different interface definition:
it uses a different scale and tail layout. Do not select it solely because a
Feetech PING or a 56/15 read succeeds.

Reference: [kissqy FT6 documentation](https://github.com/kissqy/Microduck-kissqy/blob/f02e875e73b88bf8ec7d5bbb34d0b461ac83b010/microduck-hd1910/firmware/firmware/imu-source/README_FT6_SYNC15.md).
