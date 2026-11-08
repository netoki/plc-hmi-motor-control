  VAR
    Start : BOOL AT %MX0.0 := FALSE;
    Stop : BOOL AT %MX0.1 := FALSE;
    Motor : BOOL AT %QX0.0 := FALSE;
    EStop : BOOL AT %MX0.2 := FALSE;
    Mode : BOOL AT %MX0.3 := FALSE; (* False = Manual,  True = Auto *)
    Running : BOOL AT %MX0.4 := FALSE; (* Latched run command, both modes *)
    ModeLast : BOOL := FALSE; (* Mode from previous scan *)
    ModeChanged : BOOL := FALSE; (* TRUE for one scan when Mode flips *)
    OnTmr : TON;
    OffTmr : TON;
    Cycles : CTU;
    CycleDone : BOOL := FALSE;
    FaultReset : BOOL AT %MX0.5 := FALSE; (* HMI momentary button *)
    RuntimeFault : BOOL AT %MX0.6 := FALSE; (* Exceeded maximum runtime fault, read by the HMI *)
    RunTmr : TON; (* Times continuous motor-on *)
    CycleCount : INT AT %MW0;
    FaultResetLast : BOOL := FALSE;
    ResetPulse : BOOL := FALSE;
    HeartbeatIn : INT AT %MW1;
    HeartbeatLast : INT;
    HeartbeatChanged : BOOL := FALSE;
    CommTmr : TON;
    CommFault : BOOL AT %MX0.7;
    CommArmed : BOOL AT %MX1.0 := FALSE;
    SpeedPct : INT AT %MW2;
    SpeedCmd : INT AT %MW3;
    ClampedPct : INT;
  END_VAR


(* Turns ModeChanged to true for exactly one scan upon operator switching mode.
Refer to ModeLast assignment at the bottom of this program.*)
ModeChanged := Mode <> ModeLast;

(* Rising edge: a held or stuck reset cannot clear a fault.*)
ResetPulse := FaultReset AND NOT FaultResetLast;

(*HMI Comms watchdog: faults if the heartbeat stops changing for 3 seconds.*)
HeartbeatChanged := HeartbeatIn <> HeartbeatLast;
CommArmed := HeartbeatChanged OR CommArmed;
CommTmr(IN := CommArmed AND NOT HeartbeatChanged, PT := T#3s);
CommFault := CommTmr.Q OR (CommFault AND NOT ResetPulse);

(* Running latch: Start seals in the run command. Any stop, mode change,
completed cycle, or fault drops it, so a new Start is required.*)
Running := (Start OR Running) AND NOT Stop AND NOT EStop AND NOT ModeChanged AND NOT CycleDone AND NOT RuntimeFault AND NOT CommFault AND CommArmed;

(* Auto Mode: Cycle runs for 5 seconds before resting.*)
OnTmr(IN := Running AND Mode AND NOT OffTmr.Q, PT := T#5s);

(* Auto Mode: Motor rests for 2 seconds between cycles.*)
OffTmr(IN := OnTmr.Q, PT := T#2s);

(* Auto Mode: Tracks completed cycles and resets when Running is false. 
After 3 cycles, the motor stops until started again.*)
Cycles(CU := OffTmr.Q, R := NOT Running, PV := 3);
CycleDone := Cycles.Q;
CycleCount := Cycles.CV;

(* Energizes physical motor if running in manual mode,
or currently in an active cycle within auto mode.*)
Motor := Running AND (NOT Mode OR NOT OnTmr.Q);

(*RuntimeFault Detection: Motor exceeded maximum allowed runtime.
Motor may only be physically running for 30 seconds before a forced fault, stopping the motor.
RuntimeFault latches until manually reset with fault reset button.*)
RunTmr(IN := Motor, PT := T#30s);
RuntimeFault := RunTmr.Q  OR (RuntimeFault AND NOT ResetPulse);

(*Scale operator speed to the motors usable PWM range. *)
ClampedPct := LIMIT(0, SpeedPct, 100);

if Motor then
    SpeedCmd := 90 + (ClampedPct * 165) / 100;
else
    SpeedCmd := 0;
end_if;

(*Previous-scan values for edge detection.*)
ModeLast := Mode;
FaultResetLast := FaultReset;
HeartbeatLast := HeartbeatIn;

  
