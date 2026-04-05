import serial
import sys
import time

if len(sys.argv) < 3:
    print("Usage: python upload_uart.py <COM_PORT> <BIN_FILE>")
    print("Example: python upload_uart.py COM4 neurisa_demo.bin")
    sys.exit(1)

port = sys.argv[1]
filename = sys.argv[2]
baudrate = 19200

try:
    with open(filename, 'rb') as f:
        firmware = f.read()
except Exception as e:
    print(f"Error reading file: {e}")
    sys.exit(1)

print(f"Opening port {port} at {baudrate} baud...")
try:
    ser = serial.Serial(port, baudrate, timeout=0.5)
except Exception as e:
    print(f"Error opening port: {e}")
    sys.exit(1)

print("\n>>> PLEASE PRESS THE RESET BUTTON (GPIO_SW_CENTER) ON THE BOARD NOW <<<\n")

# Wait for bootloader prompt
while True:
    data = ser.read(1024)
    if data:
        sys.stdout.write(data.decode('utf-8', errors='ignore'))
        sys.stdout.flush()
    if b"CMD:>" in data:
        break

print("\n\nBootloader ready! Triggering upload...")
ser.write(b'u')
time.sleep(0.5)

print(f"Uploading {filename} ({len(firmware)} bytes)...")
# Send in chunks to prevent overrunning the UART RX FIFO
chunk_size = 64
for i in range(0, len(firmware), chunk_size):
    ser.write(firmware[i:i+chunk_size])
    time.sleep(0.01)

time.sleep(1)

print("\nExecuting program...")
ser.write(b'e')

print("\n" + "="*50)
print("             NEURISA APPLICATION OUTPUT             ")
print("="*50 + "\n")

# Stream output forever
try:
    while True:
        data = ser.read(1024)
        if data:
            sys.stdout.write(data.decode('utf-8', errors='ignore'))
            sys.stdout.flush()
except KeyboardInterrupt:
    print("\nExiting...")
finally:
    ser.close()
