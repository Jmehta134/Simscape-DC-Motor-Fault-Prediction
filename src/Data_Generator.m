modelName = 'DCMotor_Model';
nSims = 300;
stopTime = 2.0;
noiseLevel = 0.02;

results = table('Size',[nSims 9], ...
    'VariableTypes',{'double','double','double','double','double','double','double','double','string'}, ...
    'VariableNames',{'Friction','Resistance','MaxCurrent','AvgSpeed','RMS_Current','Kurtosis_Speed','P2P_Current','SettleTime','HealthStatus'});

fprintf('Starting Digital Twin Ensemble Generation...\n');

for i = 1:nSims
    % Friction (B_wear): Healthy is low, Wear increases it
    B_wear = 0.001 + (rand * 0.015); 
    % Resistance (R_fault): Healthy is ~1.2, Heat/Shorts increase it
    R_fault = 1.2 + (rand * 5.0);
    
    assignin('base', 'B_wear', B_wear);
    assignin('base', 'R_fault', R_fault);
    
    simOut = sim(modelName, 'StopTime', num2str(stopTime));
    
    speedTS = simOut.logsout.get('motor_speed').Values;
    currTS  = simOut.logsout.get('motor_current').Values;
    
    t = speedTS.Time;
    s_raw = speedTS.Data;
    c_raw = currTS.Data;
    
    %% Feature Engineering (Mathematical Processing)
    % Here we treat s_raw/c_raw as if they were noisy sensor data
    
    % Feature 1: Peak Current (Sensitive to electrical faults)
    results.MaxCurrent(i) = max(c_raw);
    
    % Feature 2: Steady State Speed (Sensitive to mechanical friction)
    results.AvgSpeed(i) = mean(s_raw(end-50:end)); 
    
    % Feature 3: RMS Current (The 'Heavy Lifting' feature)
    results.RMS_Current(i) = rms(c_raw);
    
    % Feature 4: Kurtosis (Measures 'spikiness' of speed signal)
    results.Kurtosis_Speed(i) = kurtosis(s_raw);
    
    % Feature 5: Peak-to-Peak Current
    results.P2P_Current(i) = peak2peak(c_raw);
    
    % Feature 6: Settling Time (Time to reach 95% of final speed)
    finalSpd = results.AvgSpeed(i);
    idx = find(s_raw >= 0.95 * finalSpd, 1);
    if ~isempty(idx)
        results.SettleTime(i) = t(idx);
    else
        results.SettleTime(i) = stopTime;
    end
    
    % the ground-truth fault values
    results.Friction(i) = B_wear;
    results.Resistance(i) = R_fault;
    
    %% Health Labeling (The Target for the classification)
    if B_wear > 0.012 || R_fault > 5.0
        results.HealthStatus(i) = "Critical Failure";
    elseif B_wear > 0.007 || R_fault > 3.0
        results.HealthStatus(i) = "Maintenance Needed";
    else
        results.HealthStatus(i) = "Healthy";
    end
    
    if mod(i,10)==0, fprintf('Progress: %d%%\n', (i/nSims)*100); end
end