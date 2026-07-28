%% 1. Load the Raspberry Pi Data
% Replace with your actual Pi CSV filename
pi_filename = "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-16-35GrandC3"; 
pi_data = readtable(pi_filename);

raw_time_pi = pi_data.Time; 
ax_pi = pi_data.X;
ay_pi = pi_data.Y;
az_pi = pi_data.Z;

%% 2. Time Synchronization (Pi Clock)
if isdatetime(raw_time_pi)
    elapsed_time_pi = seconds(raw_time_pi - raw_time_pi(1)); 
else
    elapsed_time_pi = raw_time_pi - raw_time_pi(1); 
end

%% 3. Signal Processing: Vector Magnitude & Filtering
% Combine axes to remove sensor tilt and gravity direction
a_total_pi = sqrt(ax_pi.^2 + ay_pi.^2 + az_pi.^2);

% Design a 2nd-order Butterworth High-Pass Filter
fs = 400; % Sample rate (400 Hz)
fc = 2;   % Cutoff frequency in Hz
[b, a] = butter(2, fc/(fs/2), 'high');

% Apply zero-phase filter to isolate vibration
a_filtered_pi = filtfilt(b, a, a_total_pi);

%% 4. Load and Clean the iPhone CSV Data
phone_filename = "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location3.csv"; 
phone_data = readtable(phone_filename);

% Zero the time clock using the 'seconds_elapsed' column
raw_time_phone = phone_data.seconds_elapsed;
elapsed_time_phone = raw_time_phone - raw_time_phone(1);

raw_speed = phone_data.speed; % m/s

% Clean invalid -1 speed readings and interpolate missing gaps
raw_speed(raw_speed < 0) = NaN;
clean_speed = fillmissing(raw_speed, 'linear');

%% 5. Sync Shift, Interpolation & Distance Calculation
% Adjust this offset to match the physical jolt (e.g., 0.0 seconds)
time_offset = 0.0; 
aligned_time_phone = elapsed_time_phone - time_offset;

% Stretch the slow GPS data across the 400Hz Pi time array
synced_speed = interp1(aligned_time_phone, clean_speed, elapsed_time_pi, 'linear', 'extrap');
synced_lat = interp1(aligned_time_phone, phone_data.latitude, elapsed_time_pi, 'linear', 'extrap');
synced_lon = interp1(aligned_time_phone, phone_data.longitude, elapsed_time_pi, 'linear', 'extrap');

% Calculate Cumulative Distance (Meters) using flat-earth approximation
lat_rad = deg2rad(mean(synced_lat, 'omitnan'));
dlat = [0; diff(synced_lat)] * 111000; % 1 degree latitude is approx 111,000 meters
dlon = [0; diff(synced_lon)] * 111000 * cos(lat_rad);
step_dist = sqrt(dlat.^2 + dlon.^2);
cum_dist = cumsum(step_dist); % X-axis array for plotting

%% 6. Calculate Road Roughness Index (RRI)
window_size = 400; % 1-second rolling window at 400 Hz
a_rms = sqrt(movmean(a_filtered_pi.^2, window_size));

% Floor speed to 0.5 m/s to prevent dividing by zero when stopped
safe_speed = max(synced_speed, 0.5); 
RRI = a_rms ./ (safe_speed .^ 2);

%% 7. Spectral Analysis (FFT) for Frequency Domain
L = length(a_filtered_pi);       % Length of signal
Y = fft(a_filtered_pi);          % Compute Fast Fourier Transform

% Compute the two-sided spectrum (P2) and single-sided amplitude (P1)
P2 = abs(Y / L);
P1 = P2(1:floor(L/2)+1);
P1(2:end-1) = 2 * P1(2:end-1);

% Define the frequency axis
f_axis = fs * (0:floor(L/2)) / L;

%% 8. Plotting the 4-Panel Dashboard (Distance-Based)
figure('Name', 'Road Roughness & Telemetry Dashboard', 'Color', 'w', 'Position', [100 100 1200 800]);

% Panel 1: Filtered Vibration (Spatial Domain)
subplot(2,2,1);
plot(cum_dist, a_filtered_pi, 'Color', [0 0.4470 0.7410], 'LineWidth', 0.8);
title('Isolated Mechanical Vibration');
xlabel('Distance (Meters)');
ylabel('Acceleration (g)');
grid on;

% Panel 2: Interpolated GPS Speed
subplot(2,2,2);
plot(cum_dist, synced_speed, 'Color', [0.8500 0.3250 0.0980], 'LineWidth', 1.5);
title('Bicycle Speed Profile');
xlabel('Distance (Meters)');
ylabel('Speed (m/s)');
grid on;

% Panel 3: Speed-Normalized RRI
subplot(2,2,3);
plot(cum_dist, RRI, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.2);
title('Calculated Road Roughness Index (RRI)');
xlabel('Distance (Meters)');
ylabel('RRI Score');
grid on;

% Panel 4: Single-Sided Amplitude Spectrum (Frequency Domain)
% Note: FFT inherently stays in the frequency domain (Hz), so it remains unchanged.
subplot(2,2,4);
plot(f_axis, P1, 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 1);
title('Frequency Spectrum of Vibrations (FFT)');
xlabel('Frequency (Hz)');
ylabel('|Amplitude|');
xlim([0 fs/2]); % Plot up to Nyquist frequency (200 Hz)
grid on;

%% 9. Route Evaluation Metrics (Excluding Calibration Spike)
% Define a safe starting distance to ignore the "bump-to-start" jolt
start_trim_meters = 50; 

% Create a logical mask for data that occurs AFTER the trim distance
valid_idx = cum_dist > start_trim_meters;

% Extract only the valid, moving RRI data
clean_RRI = RRI(valid_idx);

% Calculate the metrics on the clean data
route_mean = mean(clean_RRI, 'omitnan');
route_p95 = prctile(clean_RRI, 95);
route_max = max(clean_RRI, [], 'omitnan');
total_distance = cum_dist(end);

% Print the results cleanly to the MATLAB command window
fprintf('--- Route Summary ---\n');
fprintf('Total Distance: %.2f meters\n', total_distance);
fprintf('Mean RRI:       %.4f\n', route_mean);
fprintf('95th Percentile:%.4f (Severity of typical hazards)\n', route_p95);
fprintf('Max RRI:        %.4f (Worst valid pothole)\n', route_max);
fprintf('---------------------\n');