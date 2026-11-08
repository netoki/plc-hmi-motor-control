# PLC/HMI Motor Control System

**OpenPLC · Ignition Perspective · Python · Arduino**

A learning prototype of an industrial motor control system. An operator runs a real DC motor from an Ignition Perspective HMI. All control decisions, interlocks, and fault handling live in a soft PLC (OpenPLC) programmed in Structured Text, and a Python bridge carries the final speed command to an Arduino-driven motor driver.

**Demo video:** [link]
**Comm-loss demo:** [link]

---

## Architecture

```text
Ignition Perspective HMI (browser)
        │  bindings and operator events
Ignition Gateway (tags → OPC UA server → Modbus TCP driver, 1 s heartbeat script)
        │  Modbus TCP, port 502
OpenPLC Runtime (Structured Text logic, Modbus TCP server)
        │  Modbus TCP, reads SpeedCmd
Python bridge (polls every 200 ms)
        │  USB serial, 9600 baud
Arduino Uno (PWM output, kick-start, 1 s command timeout)
        │  PWM and direction pins
L293D motor driver  ←  separate 5 V power module
        │
DC motor
```

- **OpenPLC** owns every control decision. Ignition and the Python bridge are Modbus clients that only read and write PLC memory.
- **Ignition** handles operator screens, tags, and a heartbeat that proves the HMI link is alive.
- **Python** translates between Modbus TCP and USB serial. It makes no control decisions.
- **Arduino** turns the speed command into PWM and handles fast, timing-sensitive behavior at the motor.

---

## Features

**Control logic (Structured Text)**
- Seal-in run latch with Start, Stop, and E-stop
- Auto/Manual modes; changing mode drops the run command so the motor can't restart unexpectedly
- Auto cycle: 5 s on, 2 s off, 3 cycles, then stops and waits for a new Start
- Runtime fault: motor continuously on for 30 s latches a fault
- Rising-edge fault reset, so a held or stuck reset can't clear or hide a fault
- Communications watchdog: faults if the HMI heartbeat stops changing for 3 s
- Startup interlock: the watchdog arms on the first heartbeat, and Start is blocked until it does
- Speed scaling: operator 0–100% maps to PWM 90–255; forced to 0 whenever the motor is off

**HMI (Ignition Perspective)**
- Start, Stop, E-stop, Auto/Manual, Fault Reset, and speed slider
- Motor status with distinct runtime fault and comm fault indication

**Motor control (Arduino)**
- Kick-start: 255 PWM for 200 ms when starting from stopped, to overcome static friction
- Command timeout: stops the motor if no command arrives for 1 s

---

## Hardware and software

| Hardware | Software |
|---|---|
| Elegoo Uno R3 | OpenPLC Editor and Runtime |
| L293D motor driver IC | Ignition Maker Edition (Perspective) |
| 3–6 V DC motor with fan blade | Python 3 (`pymodbus`, `pyserial`) |
| Breadboard power module (5 V), 9 V 1 A adapter | Arduino IDE |

---

## PLC variable and address map

Ignition counts Modbus addresses from 1 by default; `pymodbus` counts from 0. `%MW` words map to holding registers starting at zero-based address 1024.

| Variable | Type | PLC address | Written by | Purpose |
|---|---|---|---|---|
| `Start` | BOOL | `%MX0.0` | HMI | Start command |
| `Stop` | BOOL | `%MX0.1` | HMI | Stop command |
| `EStop` | BOOL | `%MX0.2` | HMI | Software E-stop (simulation only) |
| `Mode` | BOOL | `%MX0.3` | HMI | FALSE = Manual, TRUE = Auto |
| `Running` | BOOL | `%MX0.4` | PLC | Latched run command |
| `FaultReset` | BOOL | `%MX0.5` | HMI | Momentary fault reset |
| `RuntimeFault` | BOOL | `%MX0.6` | PLC | Max runtime exceeded |
| `CommFault` | BOOL | `%MX0.7` | PLC | HMI heartbeat lost |
| `CommArmed` | BOOL | `%MX1.0` | PLC | First heartbeat received |
| `Motor` | BOOL | `%QX0.0` | PLC | Motor output |
| `CycleCount` | INT | `%MW0` (HR 1024 / Ignition HR1025) | PLC | Completed auto cycles |
| `HeartbeatIn` | INT | `%MW1` (HR 1025 / Ignition HR1026) | Ignition script | Heartbeat counter |
| `SpeedPct` | INT | `%MW2` (HR 1026 / Ignition HR1027) | HMI | Operator speed, 0–100% |
| `SpeedCmd` | INT | `%MW3` (HR 1027 / Ignition HR1028) | PLC | Final PWM command, read by Python |

Internal-only variables (no address): `ModeLast`, `ModeChanged`, `CycleDone`, `FaultResetLast`, `ResetPulse`, `HeartbeatLast`, `HeartbeatChanged`, `ClampedPct`, and the timers and counter.

---

## Fail-safe behavior

| Failure | Detected by | Response |
|---|---|---|
| HMI stops sending heartbeats | PLC comm watchdog (3 s) | `CommFault` latches, motor stops, reset blocked until heartbeat returns |
| PLC starts before Ignition connects | `CommArmed` interlock | Start blocked until the first heartbeat; no nuisance fault |
| PLC read fails in Python | Python bridge | Sends speed 0 |
| Python bridge or USB link dies | Arduino timeout (1 s) | Motor stops |
| Motor runs too long | PLC runtime timer (15 s) | `RuntimeFault` latches, motor stops |
| Reset button held or stuck | Rising-edge detector | Fault still trips and stays visible |
| Fault cleared | Run latch | Motor stays off until a new Start |

---

## Test results

| # | Test | Expected | Result |
|---|---|---|---|
| 1 | Auto cycle | 5 s on / 2 s off × 3, then stop | Pass |
| 2 | Runtime fault (Manual) | Fault at 15 s, motor stops | Pass |
| 3 | Reset held through 15 s | Fault trips and stays latched | Pass (after fix) |
| 4 | Mode change while running | Motor stops, waits for new Start | Pass |
| 5 | Fault cleared | Motor stays off until new Start | Pass |
| 6 | Heartbeat stopped | `CommFault` within ~3 s, motor stops | Pass |
| 7 | Reset with heartbeat still missing | `CommFault` stays latched | Pass |
| 8 | PLC restart with Ignition running | No startup fault; Start blocked until armed | Pass (after fix) |
| 9 | Speed slider on hardware | Motor speed follows slider | Pass |
| 10 | Stop on hardware | Motor stops | Pass |
| 11 | Python bridge closed while running | Motor stops within ~1 s | Pass |

---

## Bugs found and lessons learned

**Held reset could block a fault.** The original latch, `Fault := (RunTmr.Q OR Fault) AND NOT FaultReset`, let a held reset keep the fault false, so the motor could run past its limit. Fixed by making the fault condition take priority: `RunTmr.Q OR (Fault AND NOT ...)`.

**Fault was invisible with reset held.** After that fix, the motor stopped correctly, but the fault cleared after one scan, too fast for the HMI to show. Fixed with a rising-edge `ResetPulse`, so only a new press can clear a fault. Lesson: safe behavior and visible behavior are both requirements.

**Startup comm fault.** The watchdog tripped on every PLC start because the timer began before Ignition reconnected. Fixed with a `CommArmed` interlock instead of lengthening the timeout, which would have slowed real fault detection.

**Relay clicked but never switched off.** In early relay testing, the stop state reversed the coil's polarity instead of de-energizing it. The relay coil is non-polarized, so it stayed pulled in. Fixed by driving both coil-side outputs low. The final build drives the motor directly from the L293D, since a relay can't handle PWM.

**Motor deadband.** Measured on hardware: the motor needs about 130/255 PWM to start but keeps running down to about 75. This static-versus-running friction gap shaped the design: a 90 PWM minimum running speed and a short kick-start.

**Modbus off-by-one.** Ignition shows `SpeedCmd` as `HR1028`, but `pymodbus` reads it at `1027` because of 1-based versus 0-based addressing.

---

## Limitations

This is a learning prototype, not a production design.

- The E-stop is software only. A real machine needs a hardwired E-stop through a safety relay or safety PLC that removes power independently of the HMI, network, and PLC program.
- OpenPLC runs on a desktop PC, not real-time or safety-rated hardware.
- Breadboard wiring, no industrial I/O, enclosure, or circuit protection.
- An L293D stands in for a motor drive; an industrial system would use a VFD or servo drive.
- The heartbeat comes from the Ignition Gateway, so a frozen operator browser would not trip the watchdog.

---

## Repository layout

```text
plc/        Structured Text program and OpenPLC project
ignition/   Ignition project and tag exports
bridge/     motor_bridge.py
arduino/    Motor control sketch
docs/       Wiring schematic and architecture diagram
media/      Screenshots
```

## Running it

1. Start the OpenPLC Runtime, upload the Structured Text program, and confirm the Modbus server is enabled on port 502.
2. Start the Ignition Gateway and confirm the Modbus device shows Connected.
3. Upload the Arduino sketch, then close Serial Monitor.
4. Power the motor supply module.
5. `py -m pip install pymodbus pyserial`, set `SERIAL_PORT` and `SPEED_REGISTER` in `motor_bridge.py`, then run `py motor_bridge.py`.
6. Open the Perspective HMI and press Start.

## AI use

I built this project with AI assistance for explanations, code review, and drafting parts of the Python bridge and Arduino sketch. I wrote the Structured Text logic, built and wired the hardware, and ran and verified every test above.
