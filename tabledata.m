%% Master Table Generator for LaTeX
% This script runs your exact DSP math for all routes and formats 
% the output specifically for your IEEE LaTeX table.

route_names = ["Mosholu Parkway", "Central Park", "West Side Highway", "Reservoir", "Convent Ave", "Grand Concourse"];

pi_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\RRI_Data_2026-07-25_20-08-17Mosholu",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\RRI_Data_2026-07-23_18-47-38CENTRALPARK",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\RRI_Data_2026-07-23_19-25-33WESTSIDEHIGHWAY",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\RRI_Data_2026-07-25_19-46-25Resevoir",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\RRI_Data_2026-07-23_18-17-58CONVENTLOOP",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-16-35GrandC3" % Using your updated GrandC3 file
];

phone_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location3.csv" % Using your updated GrandC3 location
];

num_routes = length(route_names);
fprintf('\n--- COPY AND PASTE THIS INTO YOUR LATEX TABLE ---\n\n');

for i = 1:num_routes
    % 1. Load Pi Data
    pi_data = readtable(pi_files(i));
    if isdatetime(pi_data.Time)
        elapsed_time_pi = seconds(pi_data.Time - pi_data.Time(1));
    else
        elapsed_time_pi = pi_data.Time - pi_data.Time(1);
    end
    
    % 2. DSP Pipeline
    a_total_pi = sqrt(pi_data.X.^2 + pi_data.Y.^2 + pi_data.Z.^2);
    [b, a] = butter(2, 2/(400/2), 'high');
    a_filtered_pi = filtfilt(b, a, a_total_pi);
    
    % 3. Load Phone Data
    phone_data = readtable(phone_files(i));
    elapsed_time_phone = phone_data.seconds_elapsed - phone_data.seconds_elapsed(1);
    raw_speed = phone_data.speed;
    raw_speed(raw_speed < 0) = NaN;
    clean_speed = fillmissing(raw_speed, 'linear');
    
    % 4. Interpolation & Distance
    synced_speed = interp1(elapsed_time_phone, clean_speed, elapsed_time_pi, 'linear', 'extrap');
    synced_lat = interp1(elapsed_time_phone, phone_data.latitude, elapsed_time_pi, 'linear', 'extrap');
    synced_lon = interp1(elapsed_time_phone, phone_data.longitude, elapsed_time_pi, 'linear', 'extrap');
    
    lat_rad = deg2rad(mean(synced_lat, 'omitnan'));
    dlat = [0; diff(synced_lat)] * 111000;
    dlon = [0; diff(synced_lon)] * 111000 * cos(lat_rad);
    cum_dist = cumsum(sqrt(dlat.^2 + dlon.^2));
    
    % 5. RRI Calculation
    a_rms = sqrt(movmean(a_filtered_pi.^2, 400));
    safe_speed = max(synced_speed, 0.5); 
    RRI = a_rms ./ (safe_speed .^ 2);
    
    % 6. Metrics (Applying your 50m trim rule)
    valid_idx = cum_dist > 50;
    clean_RRI = RRI(valid_idx);
    clean_speed_masked = synced_speed(valid_idx);
    
    route_mean = mean(clean_RRI, 'omitnan');
    route_p95 = prctile(clean_RRI, 95);
    route_max = max(clean_RRI, [], 'omitnan');
    total_dist = cum_dist(end);
    avg_vel = mean(clean_speed_masked, 'omitnan');
    
    % 7. Print formatted LaTeX row
    fprintf('%-20s & %7.1f & %6.2f & %6.4f & %6.4f & %6.4f \\\\\n', ...
        route_names(i), total_dist, avg_vel, route_mean, route_p95, route_max);
end

fprintf('\n-------------------------------------------------\n');