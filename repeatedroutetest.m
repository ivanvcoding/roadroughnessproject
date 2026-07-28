
pi_files = { ...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_18-44-22GrandC0", ...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_18-55-20GrandC1",...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-05-22GrandC2",...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-16-35GrandC3"};

phone_files = { ...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location0.csv",...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location1.csv", ...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location2.csv",...
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location3.csv"};

num_runs = length(pi_files);
clear runs; 

for k = 1:num_runs
    pi_data = readtable(pi_files{k});
    raw_time_pi = pi_data.Time;
    
    if isdatetime(raw_time_pi)
        t_pi = seconds(raw_time_pi - raw_time_pi(1));
    else
        t_pi = raw_time_pi - raw_time_pi(1);
    end
    

    a_total = sqrt(pi_data.X.^2 + pi_data.Y.^2 + pi_data.Z.^2);
    

    phone_data = readtable(phone_files{k});
    t_phone = phone_data.seconds_elapsed - phone_data.seconds_elapsed(1);
    
    clean_speed = phone_data.speed;
    clean_speed(clean_speed < 0) = NaN;
    clean_speed = fillmissing(clean_speed, 'linear');
    

    speed_400Hz = interp1(t_phone, clean_speed, t_pi, 'linear', 'extrap');
    lat_400Hz   = interp1(t_phone, phone_data.latitude, t_pi, 'linear', 'extrap');
    lon_400Hz   = interp1(t_phone, phone_data.longitude, t_pi, 'linear', 'extrap');
    
    lat_rad = deg2rad(mean(lat_400Hz, 'omitnan'));
    dlat = [0; diff(lat_400Hz)] * 111000; 
    dlon = [0; diff(lon_400Hz)] * 111000 * cos(lat_rad);
    step_dist = sqrt(dlat.^2 + dlon.^2);
    cum_dist = cumsum(step_dist);
    
    runs(k).dist = cum_dist;
    runs(k).accel = a_total;
    runs(k).speed = speed_400Hz;
end

figure('Name', '4-Run Repeatability Analysis', 'Color', 'w', 'Position', [100 100 1000 800]);

colors = [
    0.00 0.45 0.74; % Blue   (Run 1)
    0.85 0.33 0.10; % Red    (Run 2 - GPS Spike)
    0.93 0.69 0.13; % Yellow (Run 3)
    0.47 0.67 0.19  % Green  (Run 4)
];

subplot(2,1,1);
hold on;
for k = 1:num_runs
    % We use a slight transparency (Color with 4th element) so overlapping spikes are visible
    plot(runs(k).dist, runs(k).accel, 'Color', [colors(k,:) 0.7], 'LineWidth', 0.5, ...
        'DisplayName', sprintf('Run %d', k));
end
title('Raw Acceleration Magnitude Repeatability (Milled Surface)');
ylabel('Acceleration (g)');
xlim([0 max(runs(1).dist)]); % Align to the length of the first run
legend('Location', 'northeast');
grid on; hold off;

subplot(2,1,2);
hold on;
for k = 1:num_runs
    plot(runs(k).dist, runs(k).speed, 'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Run %d', k));
end
title('Velocity Profile Repeatability');
xlabel('Distance along Route (Meters)');
ylabel('Speed (m/s)');
xlim([0 max(runs(1).dist)]); 
legend('Location', 'northeast');
grid on; hold off;

