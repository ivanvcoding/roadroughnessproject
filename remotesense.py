import smbus2
import RPi.GPIO as GPIO
import time
import csv
import threading
import os
import subprocess

# ==========================================
# 1. HARDWARE PINS & DSP CONSTANTS
# ==========================================
BTN_RECORD = 17
BTN_SHUTDOWN = 27
LED_READY = 22   # Green
LED_RECORD = 23  # Blue
LED_ERROR = 24   # Red

MPU_ADDRESS = 0x68
PWR_MGMT_1 = 0x6B
CONFIG_REG = 0x1A
ACCEL_CONFIG = 0x1C
ACCEL_XOUT_H = 0x3B

TARGET_SAMPLE_RATE_HZ = 400
SAMPLE_INTERVAL = 1.0 / TARGET_SAMPLE_RATE_HZ
ACCEL_SCALE = 2048.0  # Divider for +/- 16g range

# ==========================================
# 2. STATE VARIABLES & LOCKS
# ==========================================
is_recording = False
is_running = True
data_lock = threading.Lock() # Mutex lock to prevent file I/O race conditions
csv_file = None
csv_writer = None
recording_start_time = 0.0

bus = smbus2.SMBus(1)

# ==========================================
# 3. INITIALIZATION FUNCTIONS
# ==========================================
def setup_gpio():
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Setup LEDs
    GPIO.setup(LED_READY, GPIO.OUT)
    GPIO.setup(LED_RECORD, GPIO.OUT)
    GPIO.setup(LED_ERROR, GPIO.OUT)
    
    # Setup Buttons with internal Pull-Up resistors
    GPIO.setup(BTN_RECORD, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(BTN_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    # Attach asynchronous event listeners (Interrupts)
    GPIO.add_event_detect(BTN_RECORD, GPIO.FALLING, callback=toggle_recording, bouncetime=500)
    GPIO.add_event_detect(BTN_SHUTDOWN, GPIO.FALLING, callback=system_shutdown, bouncetime=1000)

def setup_mpu6050():
    try:
        # Wake up the sensor
        bus.write_byte_data(MPU_ADDRESS, PWR_MGMT_1, 0x00)
        time.sleep(0.1)
        # Set to +/- 8g range (0x10)
        bus.write_byte_data(MPU_ADDRESS, ACCEL_CONFIG, 0x18)
        # Set Digital Low Pass Filter to 0x01 (184 Hz Bandwidth) - Anti-Aliasing setup
        bus.write_byte_data(MPU_ADDRESS, CONFIG_REG, 0x01)
    except Exception as e:
        print("Sensor setup failed. Check wiring.")
        error_flash()

# ==========================================
# 4. CALLBACKS & UTILITIES
# ==========================================
def error_flash():
    """Flashes the red LED to indicate an I2C glitch without crashing."""
    GPIO.output(LED_ERROR, GPIO.HIGH)
    time.sleep(0.05)
    GPIO.output(LED_ERROR, GPIO.LOW)

def toggle_recording(channel):
    global is_recording, csv_file, csv_writer, recording_start_time
    
    # 1. Wait for 1 second to absorb any mechanical shock or accidental bumps
    time.sleep(1.0)
    
    # 2. Check if the physical button is STILL being held down
    if GPIO.input(BTN_RECORD) == GPIO.LOW:
        with data_lock: 
            is_recording = not is_recording
            
            if is_recording:
                # Start Recording: Open new CSV
                timestamp = time.strftime("%Y-%m-%d_%H-%M-%S")
                filename = f"RRI_Data_{timestamp}.csv"
                
                csv_file = open(filename, mode='w', newline='')
                csv_writer = csv.writer(csv_file)
                csv_writer.writerow(['Time', 'X', 'Y', 'Z'])
                
                recording_start_time = time.time() 
                
                GPIO.output(LED_READY, GPIO.LOW)
                GPIO.output(LED_RECORD, GPIO.HIGH) # Blue LED ON
                print(f"Started recording to {filename}")
            else:
                # Stop Recording: Safely close CSV
                if csv_file:
                    csv_file.close()
                    csv_file = None
                    
                GPIO.output(LED_RECORD, GPIO.LOW)
                GPIO.output(LED_READY, GPIO.HIGH) # Green LED ON
                print("Stopped recording.")
    else:
        # 3. If the button was released before 1 second, ignore it completely
        print("Record toggle canceled: Button was not held long enough.")
        
def system_shutdown(channel):
    global is_running
    
    # 1. Wait for 2 seconds while the user is (hopefully) holding the button
    time.sleep(2)
    
    # 2. Check the hardware pin. Is it STILL being pressed (connected to Ground/LOW)?
    if GPIO.input(BTN_SHUTDOWN) == GPIO.LOW:
        print("Shutdown button held. Halting system...")
        
        with data_lock:
            is_running = False
            if is_recording and csv_file:
                csv_file.close()
                
        GPIO.output(LED_READY, GPIO.LOW)
        GPIO.output(LED_RECORD, GPIO.LOW)
        GPIO.output(LED_ERROR, GPIO.HIGH) # Red LED solid indicating safe to unplug soon
        
        subprocess.call("sudo halt", shell=True)
    else:
        # 3. If they let go before 2 seconds, cancel the shutdown.
        print("Shutdown canceled: Button was not held long enough.")

# ==========================================
# 5. MAIN DSP LOOP
# ==========================================
def read_and_log():
    # Bitwise shift combination for MPU6050 raw data
    def twos_complement(high_byte, low_byte):
        val = (high_byte << 8) + low_byte
        if val >= 0x8000:
            val = -((65535 - val) + 1)
        return val

    print("System Ready. Waiting for button press...")
    GPIO.output(LED_READY, GPIO.HIGH) # Indicate system is alive and ready
    
    while is_running:
        loop_start_time = time.perf_counter()
        
        if is_recording:
            with data_lock:
                try:
                  # Burst read 6 bytes starting from X-axis high byte
                    data = bus.read_i2c_block_data(MPU_ADDRESS, ACCEL_XOUT_H, 6)
                    
                    # NEW: Round the acceleration math to 4 decimal places
                    x = round(twos_complement(data[0], data[1]) / ACCEL_SCALE, 4)
                    y = round(twos_complement(data[2], data[3]) / ACCEL_SCALE, 4)
                    z = round(twos_complement(data[4], data[5]) / ACCEL_SCALE, 4)
                    
                    # NEW: Calculate elapsed time and round to 4 decimal places
                    current_time = round(time.time() - recording_start_time, 4)
                    
                    if csv_writer:
                        csv_writer.writerow([current_time, x, y, z])
                except OSError:
                    # If breadboard wires bounce, skip this reading but KEEP RUNNING
                    error_flash()
                    pass 

        # Dynamic Sleep: Keeps the loop consistently at 400 Hz regardless of CPU load
        elapsed = time.perf_counter() - loop_start_time
        time_to_wait = SAMPLE_INTERVAL - elapsed
        if time_to_wait > 0:
            time.sleep(time_to_wait)

# ==========================================
# 6. EXECUTION
# ==========================================
if __name__ == '__main__':
    setup_gpio()
    setup_mpu6050()
    try:
        read_and_log()
    except KeyboardInterrupt:
        pass
    finally:
        GPIO.cleanup()