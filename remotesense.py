import smbus2
import RPi.GPIO as GPIO
import time
import csv
import threading
import os
import subprocess

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
ACCEL_SCALE = 2048.0  

is_recording = False
is_running = True
data_lock = threading.Lock() 
csv_file = None
csv_writer = None
recording_start_time = 0.0

bus = smbus2.SMBus(1)

def setup_gpio():
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    
    GPIO.setup(LED_READY, GPIO.OUT)
    GPIO.setup(LED_RECORD, GPIO.OUT)
    GPIO.setup(LED_ERROR, GPIO.OUT)
    
    
    GPIO.setup(BTN_RECORD, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(BTN_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    
    GPIO.add_event_detect(BTN_RECORD, GPIO.FALLING, callback=toggle_recording, bouncetime=500)
    GPIO.add_event_detect(BTN_SHUTDOWN, GPIO.FALLING, callback=system_shutdown, bouncetime=1000)

def setup_mpu6050():
    try:
       
        bus.write_byte_data(MPU_ADDRESS, PWR_MGMT_1, 0x00)
        time.sleep(0.1)
        
        bus.write_byte_data(MPU_ADDRESS, ACCEL_CONFIG, 0x18)
        
        bus.write_byte_data(MPU_ADDRESS, CONFIG_REG, 0x01)
    except Exception as e:
        print("Sensor setup failed. Check wiring.")
        error_flash()

def error_flash():
    """Flashes the red LED to indicate an I2C glitch without crashing."""
    GPIO.output(LED_ERROR, GPIO.HIGH)
    time.sleep(0.05)
    GPIO.output(LED_ERROR, GPIO.LOW)

def toggle_recording(channel):
    global is_recording, csv_file, csv_writer, recording_start_time
    
    
    time.sleep(1.0)
    
   
    if GPIO.input(BTN_RECORD) == GPIO.LOW:
        with data_lock: 
            is_recording = not is_recording
            
            if is_recording:
                
                timestamp = time.strftime("%Y-%m-%d_%H-%M-%S")
                filename = f"RRI_Data_{timestamp}.csv"
                
                csv_file = open(filename, mode='w', newline='')
                csv_writer = csv.writer(csv_file)
                csv_writer.writerow(['Time', 'X', 'Y', 'Z'])
                
                recording_start_time = time.time() 
                
                GPIO.output(LED_READY, GPIO.LOW)
                GPIO.output(LED_RECORD, GPIO.HIGH)
                print(f"Started recording to {filename}")
            else:
                if csv_file:
                    csv_file.close()
                    csv_file = None
                    
                GPIO.output(LED_RECORD, GPIO.LOW)
                GPIO.output(LED_READY, GPIO.HIGH) 
                print("Stopped recording.")
    else:
        print("Record toggle canceled: Button was not held long enough.")
        
def system_shutdown(channel):
    global is_running
    

    time.sleep(2)
    
    if GPIO.input(BTN_SHUTDOWN) == GPIO.LOW:
        print("Shutdown button held. Halting system...")
        
        with data_lock:
            is_running = False
            if is_recording and csv_file:
                csv_file.close()
                
        GPIO.output(LED_READY, GPIO.LOW)
        GPIO.output(LED_RECORD, GPIO.LOW)
        GPIO.output(LED_ERROR, GPIO.HIGH) 
        
        subprocess.call("sudo halt", shell=True)
    else:
        print("Shutdown canceled: Button was not held long enough.")

# ==========================================
# 5. MAIN DSP LOOP
# ==========================================
def read_and_log():

    def twos_complement(high_byte, low_byte):
        val = (high_byte << 8) + low_byte
        if val >= 0x8000:
            val = -((65535 - val) + 1)
        return val

    print("System Ready. Waiting for button press...")
    GPIO.output(LED_READY, GPIO.HIGH)
    
    while is_running:
        loop_start_time = time.perf_counter()
        
        if is_recording:
            with data_lock:
                try:
                    data = bus.read_i2c_block_data(MPU_ADDRESS, ACCEL_XOUT_H, 6)
                    

                    x = round(twos_complement(data[0], data[1]) / ACCEL_SCALE, 4)
                    y = round(twos_complement(data[2], data[3]) / ACCEL_SCALE, 4)
                    z = round(twos_complement(data[4], data[5]) / ACCEL_SCALE, 4)
                    

                    current_time = round(time.time() - recording_start_time, 4)
                    
                    if csv_writer:
                        csv_writer.writerow([current_time, x, y, z])
                except OSError:
                    error_flash()
                    pass 

        elapsed = time.perf_counter() - loop_start_time
        time_to_wait = SAMPLE_INTERVAL - elapsed
        if time_to_wait > 0:
            time.sleep(time_to_wait)

if __name__ == '__main__':
    setup_gpio()
    setup_mpu6050()
    try:
        read_and_log()
    except KeyboardInterrupt:
        pass
    finally:
        GPIO.cleanup()
