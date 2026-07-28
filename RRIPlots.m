route_names = ["Central Park", "Convent", "Mosholu", "Reservoir", "West Side Highway", "Grand Concourse"];

pi_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\RRI_Data_2026-07-23_18-47-38CENTRALPARK",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\RRI_Data_2026-07-23_18-17-58CONVENTLOOP",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\RRI_Data_2026-07-25_20-08-17Mosholu",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\RRI_Data_2026-07-25_19-46-25Resevoir",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\RRI_Data_2026-07-23_19-25-33WESTSIDEHIGHWAY",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-05-22GrandC2"
];

phone_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location2.csv"
];


num_routes = length(route_names);
routes(num_routes) = struct();

for i = 1:num_routes
    fprintf('Processing %s...\n', route_names(i));
    
   
    pi_data = readtable(pi_files(i));
    raw_time_pi = pi_data.Time; 
    
    if isdatetime(raw_time_pi)
        elapsed_time_pi = seconds(raw_time_pi - raw_time_pi(1)); 
    else
        elapsed_time_pi = raw_time_pi - raw_time_pi(1); 
    end
    
   
    a_raw_total = sqrt(pi_data.X.^2 + pi_data.Y.^2 + pi_data.Z.^2);
    
   
    fs = 400; % Sample rate (400 Hz)
    fc = 2;   % Cutoff frequency
    [b, a] = butter(2, fc/(fs/2), 'high');
    a_filtered = filtfilt(b, a, a_raw_total);
    
    
    phone_data = readtable(phone_files(i));
    raw_time_phone = phone_data.seconds_elapsed;
    elapsed_time_phone = raw_time_phone - raw_time_phone(1);
    
    raw_speed = phone_data.speed; % m/s
    raw_speed(raw_speed < 0) = NaN;
    clean_speed = fillmissing(raw_speed, 'linear');
    
    
    synced_speed = interp1(elapsed_time_phone, clean_speed, elapsed_time_pi, 'linear', 'extrap');
    synced_lat = interp1(elapsed_time_phone, phone_data.latitude, elapsed_time_pi, 'linear', 'extrap');
    synced_lon = interp1(elapsed_time_phone, phone_data.longitude, elapsed_time_pi, 'linear', 'extrap');
    
    lat_rad = deg2rad(mean(synced_lat, 'omitnan'));
    dlat = [0; diff(synced_lat)] * 111000; 
    dlon = [0; diff(synced_lon)] * 111000 * cos(lat_rad);
    step_dist = sqrt(dlat.^2 + dlon.^2);
    c_dist = cumsum(step_dist); 
    
    
    L = length(a_filtered);      
    Y = fft(a_filtered);          
    P2 = abs(Y / L);
    P1 = P2(1:floor(L/2)+1);
    P1(2:end-1) = 2 * P1(2:end-1);
    f_axis = fs * (0:floor(L/2)) / L;
    
    
    routes(i).name = route_names(i);
    routes(i).distance = c_dist;
    routes(i).raw_accel = a_raw_total;
    routes(i).filt_accel = a_filtered;
    routes(i).speed = synced_speed;
    routes(i).f_axis = f_axis;
    routes(i).fft_amp = P1;
end

for i = 1:num_routes
    % Create a new figure for each route with a cascading position
    figure('Name', sprintf('Dashboard - %s', routes(i).name), ...
           'Color', 'w', 'Position', [100+(i*30) 50+(i*30) 1200 800]);
    
    %Raw Acceleration vs. Distance 
    subplot(2,2,1);
    plot(routes(i).distance, routes(i).raw_accel, 'Color', [0 0.4470 0.7410], 'LineWidth', 0.5);
    title(sprintf('%s: Raw Acceleration Magnitude (Includes Gravity)', routes(i).name));
    xlabel('Distance (Meters)');
    ylabel('Acceleration (g)');
    grid on;
    
    % Filtered Acceleration vs. Distance 
    subplot(2,2,2);
    plot(routes(i).distance, routes(i).filt_accel, 'Color', [0.8500 0.3250 0.0980], 'LineWidth', 0.5);
    title('Filtered Mechanical Vibration (> 2 Hz)');
    xlabel('Distance (Meters)');
    ylabel('Acceleration (g)');
    grid on;
    
    % Velocity vs. Distance
    subplot(2,2,3);
    plot(routes(i).distance, routes(i).speed, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.5);
    title('Velocity Profile');
    xlabel('Distance (Meters)');
    ylabel('Speed (m/s)');
    grid on;
    
    % FFT (Frequency Domain)
    subplot(2,2,4);
    plot(routes(i).f_axis, routes(i).fft_amp, 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 1.2);
    title('Spectral Comparison (FFT)');
    xlabel('Frequency (Hz)');
    ylabel('|Amplitude|');
    xlim([0 fs/2]); % Plot up to Nyquist frequency (200 Hz)
    grid on;
end
