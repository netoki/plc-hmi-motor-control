import time

import serial
from pymodbus.client import ModbusTcpClient

PLC_HOST = "127.0.0.1"
PLC_PORT = 502
SPEED_REGISTER = 1027
SERIAL_PORT = "COM3"   
BAUD_RATE = 9600
UPDATE_SECONDS = 0.2


class MotorBridge:
    """Reads SpeedCmd from the PLC and sends it to the Arduino."""

    def __init__(self):
        self.plc = ModbusTcpClient(PLC_HOST, port=PLC_PORT)
        self.arduino = None

    def connect(self):
        self.arduino = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        time.sleep(2)  # Opening the port resets the Arduino
        self.plc.connect()

    def read_speed(self):
        try:
            if not self.plc.connected:
                self.plc.connect()

            result = self.plc.read_holding_registers(SPEED_REGISTER, count=1)
            if result.isError():
                return 0
            return max(0, min(255, result.registers[0]))
        except Exception as error:
            print(f"PLC read failed: {error}")
            self.plc.close()
            return 0

    def send_speed(self, speed):
        self.arduino.write(f"{speed}\n".encode())

    def run(self):
        self.connect()
        print("Bridge running. Press Ctrl+C to stop.")

        try:
            while True:
                speed = self.read_speed()
                self.send_speed(speed)
                print(f"Speed command: {speed}")
                time.sleep(UPDATE_SECONDS)
        finally:
            self.send_speed(0)
            self.arduino.close()
            self.plc.close()


if __name__ == "__main__":
    MotorBridge().run()