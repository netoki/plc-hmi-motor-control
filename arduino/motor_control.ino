const int EN = 5;
const int IN1 = 3;
const int IN2 = 4;
const unsigned long KICK_MS = 200;
const unsigned long TIMEOUT_MS = 1000;

int currentSpeed = 0;
unsigned long lastCommand = 0;

void applySpeed(int newSpeed) {
  if (newSpeed == currentSpeed) return;

  if (currentSpeed == 0 && newSpeed > 0) {
    analogWrite(EN, 255);  // Kick-start past static friction
    delay(KICK_MS);
  }

  analogWrite(EN, newSpeed);
  currentSpeed = newSpeed;
}

void setup() {
  pinMode(EN, OUTPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  analogWrite(EN, 0);

  Serial.begin(9600);
  Serial.setTimeout(50);
}

void loop() {
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();

    if (command.length() > 0) {
      lastCommand = millis();
      applySpeed(constrain(command.toInt(), 0, 255));
    }
  }

  if (currentSpeed != 0 && millis() - lastCommand > TIMEOUT_MS) {
    applySpeed(0);  // Lost commands: stop the motor
  }
}
