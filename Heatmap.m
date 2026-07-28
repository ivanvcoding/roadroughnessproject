%% Master Geospatial RRI Heat Map (City-Wide)
% Add all your routes to these arrays. 
% Make sure the Pi file at index 1 matches the Phone file at index 1!

pi_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\RRI_Data_2026-07-23_18-47-38CENTRALPARK",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\RRI_Data_2026-07-23_18-17-58CONVENTLOOP",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\RRI_Data_2026-07-25_20-08-17Mosholu",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\RRI_Data_2026-07-23_19-25-33WESTSIDEHIGHWAY",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\RRI_Data_2026-07-25_19-05-22GrandC2",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\RRI_Data_2026-07-25_19-46-25Resevoir"
];

phone_files = [
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Central Park\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Convent\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Mosholu\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\WestSideHighway\Location.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\GrandConcourse\Location2.csv",
    "D:\ivanv\Documents\Summer2026IndependentStudy\RouteData\Reservoir\Location.csv"
];

% --- 1. Initialize Master Arrays to hold all data ---
all_lat = [];
all_lon = [];
all_RRI = [];

num_routes = length(pi_files);

% --- 2. Processing Loop ---
for i = 1:num_routes
    fprintf('Processing route %d of %d...\n', i, num_routes);
    
    % Load Pi Data
    pi_data = readtable(pi_files(i));
    if isdatetime(pi_data.Time)
        t_pi = seconds(pi_data.Time - pi_data.Time(1));
    else
        t_pi = pi_data.Time - pi_data.Time(1);
    end

    % Raw Magnitude, High-Pass Zero-Phase Filter, and RMS Window
    a_total = sqrt(pi_data.X.^2 + pi_data.Y.^2 + pi_data.Z.^2);
    [b, a] = butter(2, 2/(400/2), 'high');
    a_filt = filtfilt(b, a, a_total);
    a_rms = sqrt(movmean(a_filt.^2, 400)); % 1-second rolling window

    % Load and Interpolate Phone Data
    phone_data = readtable(phone_files(i));
    t_phone = phone_data.seconds_elapsed - phone_data.seconds_elapsed(1);

    clean_speed = phone_data.speed;
    clean_speed(clean_speed < 0) = NaN;
    clean_speed = fillmissing(clean_speed, 'linear');

    % Sync GPS to 400 Hz Pi time vector
    speed_400Hz = interp1(t_phone, clean_speed, t_pi, 'linear', 'extrap');
    lat_400Hz   = interp1(t_phone, phone_data.latitude, t_pi, 'linear', 'extrap');
    lon_400Hz   = interp1(t_phone, phone_data.longitude, t_pi, 'linear', 'extrap');

    % Calculate RRI
    safe_speed = max(speed_400Hz, 0.5); % Prevent division by zero
    RRI = a_rms ./ (safe_speed .^ 2);

    % Downsample from 400Hz to 10Hz to prevent MATLAB UI lag
    ds = 40; 
    
    % Append to master arrays (using column vectors)
    all_lat = [all_lat; lat_400Hz(1:ds:end)];
    all_lon = [all_lon; lon_400Hz(1:ds:end)];
    all_RRI = [all_RRI; RRI(1:ds:end)];
end

fprintf('All routes processed. Generating map...\n');

% --- 3. Establish Global Scale (Consistency) ---
% Cap RRI at the 95th percentile of the ENTIRE dataset
rri_cap = prctile(all_RRI, 95);
all_RRI(all_RRI > rri_cap) = rri_cap;

% --- 4. Generate Geospatial Heat Map ---
figure('Name', 'City-Wide RRI Heat Map', 'Color', 'w', 'Position', [100 100 1000 800]);

% geoscatter(lat, lon, dot_size, color_data, 'filled')
geoscatter(all_lat, all_lon, 15, all_RRI, 'filled', 'MarkerEdgeColor', 'none', 'MarkerFaceAlpha', 0.8);

% Customize the Map Appearance
geobasemap('streets'); % Try 'darkwater' or 'streets-dark' if you want the colors to really pop

% Apply the Traffic Light Colormap
balanced_colors = [
    0.20, 0.80, 0.20;  % Green (Smooth)
    1.00, 0.90, 0.20;  % Yellow (Mild)
    1.00, 0.50, 0.00;  % Orange (Moderate)
    0.85, 0.15, 0.15;  % Red (Severe Hazard)
    0.50, 0.00, 0.00   % Dark Red (Max)
];
balanced_cmap = interp1(linspace(0, 1, 5), balanced_colors, linspace(0, 1, 256));
colormap(balanced_cmap);

% Add Colorbar and Labels
c = colorbar;
c.Label.String = 'Road Roughness Index (RRI)';
c.Label.FontSize = 12;
c.Label.FontWeight = 'bold';
c.Limits = [0 rri_cap];

title('Geospatial Pavement Diagnostics: Aggregate Route Analysis', 'FontSize', 14);
subtitle('Color represents velocity-normalized kinetic energy transfer across NYC', 'FontSize', 11);