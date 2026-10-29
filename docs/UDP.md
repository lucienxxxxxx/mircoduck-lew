# Microduck phone UDP v2

The Python gateway listens on UDP 20043 and translates a fixed set of operations to existing robotd JSON-RPC over `/run/robotd.sock`. It never opens the servo UART. The robotd binary and API40 remain unchanged.

## Keyless LAN framing

Every datagram is at most 1400 bytes and contains one plain UTF-8 JSON object:

```json
{"v":2,"op":"hello","sid":"0123456789abcdef0123456789abcdef","seq":1}
```

DuckPilot 0.4 removes pairing keys and HMAC at the user’s request. Anyone able to reach this UDP port can start a control session. This is a trusted local-network interface. There is no authentication or encryption. Old v1 signed envelopes are rejected; update the App and gateway together. Nonfinite numbers and wrong versions are rejected.

Payloads include `v:2`, `sid` (fresh random 16-byte lowercase hex nonce), integer `seq` in `[0, 2^53)`, and `op`. A client starts with `hello`; no actuator intent is emitted. One endpoint/session is accepted at a time. Replayed hello nonces are rejected for the gateway process lifetime (bounded budget of 4096; restart when exhausted). Server sequences are independent from client sequences.

After hello, each request echoes a server-issued `ticket`. Tickets rotate approximately every 350–400 ms and have an absolute 450 ms validity from issue. A short overlap accepts the preceding ticket only until its original expiry, tolerating a packet delivery race without extending buffered input lifetime. Requests must advance the client sequence; endpoint, session and ticket all have to match. The server sends status at 10 Hz, carrying fresh tickets; a client must keep draining its receive queue.

## Stateless discovery (0.4.1)

`discover` carries a random 32-hex `nonce`. The response echoes it with `service:mircoduck-lew`, `control_port`, `camera_port` and `busy`. It does not create or renew a session, acquire input, or send actuator commands. The Android App probes only its current Wi-Fi gateway; see [AP auto-connect](AP-AUTO-CONNECT.md).

## Requests

| op | Fields and behavior |
| --- | --- |
| hello | Fresh sid and seq. Returns hello with accepted=true, timeout=300 ms and mapping `r17-xbox-v1` |
| ping | Heartbeat; returns pong. Never renews input ownership |
| claim | Explicit neutral frame, obtains shared kernel input lease if available. Does not HOME or enable torque |
| frame | `frame:{axes:{lx,ly,rx,ry,lt,rt,dx,dy},buttons:[...]}`; requires claimed session |
| release | Clears this phone's continuous input and lease; optional `disconnect:true` also closes the session for immediate reconnect; no implicit relax/shutdown |
| action | Fixed actions `home`, `relax`, `policy-off`, `policy-on`, `chirp`, `motion`, `commissioning`, or allowlisted skills; requires claim |

Axes are finite numbers in [-1,1], except LT/RT in [0,1]. Direction axes are -1/0/1. Buttons: start/select/a/b/x/y/lb/rb; the App exposes explicit confirmed relax instead of raw Select/shutdown. The shared helper enforces the existing R17 intent mapping and authoritative `pad.bindings` lookup.

`ack` includes `reply` (request seq), `accepted`, `claimed` and an optional reason. An accepted mode request means the worker started, not that mode changed. Subsequent status includes `mode_job:{success:null|true|false,message:...}`; actual mode and feedback are authoritative. Errors for valid current-session requests include `reply` and `reason`. Unknown endpoints or malformed packets get no response.

300 ms without accepted input clears ownership. A 2-second session heartbeat timeout removes the session. Physical gamepad presence preempts phone input. Updated console helpers and the gateway share `/run/lock/mircoduck-input.lock` via kernel flock; old unpatched helpers are outside that coordination and should be updated. After timeout, a frame cannot silently reacquire ownership: a new explicit claim is required. No commands are retransmitted automatically by the App.

## Telemetry

`status` includes actual mode/phase/build, sample age and freshness, homed/policy/torque, loop Hz, gravity `g`, gyro (rad/s), IMU valid/sequence, physical-gamepad presence and current input mode. It also includes `sitting` and available `skills`, refreshed from robot.policies. Unknown fields are null, not fabricated zeros. Freshness combines source sample age with adapter receive age; motion also requires recent robot.state subscription data.

DuckPilot 0.3 adds fixed actions `policy-on` (robot.enable on=true) and `chirp`
(robot.sound chirp), and uses the actual `sit_toggle` skill name. Legacy
`sitstand` is translated to `sit_toggle`. Continuous long-call input uses the
existing LT mapping with the same expiry behavior. These actions are retained in v2. The UI acquires the lease internally on explicit user input; hello
and camera connection still emit no actuator commands.

Two `joints` packets carry parts 0 and 1 (8 and 7 rows). Each row:

```text
[id, position_rad|null, position_raw|null, temperature_c|null,
 voltage_v|null, current_raw|null, target_rad|null, feedback_fresh, age_ms|null]
```

ID order follows the deployed 15 joints. A stale individual joint is not made fresh by a fresh bus frame or the other packet part. The App blanks stale joint values and displays raw current counts. Commissioning position angles can be unavailable.

## Deployment scope

`scripts/install-udp.sh` installs a root systemd adapter with fixed service management actions, filesystem restrictions and resource limits. It does not create an arbitrary shell or raw register-write API. Do not expose this port to the public internet. Source, APK and public ZIP exclude actual addresses and calibration. Private whole-system restore images deliberately preserve those machine-specific files.
