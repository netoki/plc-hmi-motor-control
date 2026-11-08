# plc-hmi-motor-control
A learning prototype of an industrial motor control system. An operator runs a real DC motor from an Ignition Perspective HMI. All control decisions, interlocks, and fault handling live in a soft PLC (OpenPLC) programmed in Structured Text, and a Python bridge carries the final speed command to an Arduino-driven motor driver.
