%% demoGroups.m
% =========================================================================
% DEMO GROUPS - LDF TRIAL FILES FOR 3 CONDITIONS x 8 ANIMALS, KNOWN EFFECTS
% =========================================================================
% Synthetic data for the "Groups & statistics" tab of Signal
% Characterization. Every file has the shape of DemoData.ldfTrials (what
% Process LDF saves): segmentedLDF (trials x samples), segmentedTime
% (-5..20 s at 10 Hz, stimulus at 0 s) and Fs, plus a truth struct.
%
%   demo = demoGroups()          writes to tempdir/NeuroAnalyzerDemo/groups
%   demo = demoGroups(folder)    writes to folder (created if needed)
%
% Design (deterministic, RandStream mt19937ar, seed 20260925):
%   Conditions  Control, Stimulated, Drug; the SAME 8 animals in each, so
%               Control vs Stimulated is a paired comparison (file k of
%               each condition = animal k).
%   Response    gamma-shaped hyperemia peaking 4 s after onset (as in
%               DemoData) on a ~110-130 PU baseline, with vasomotion
%               (0.13 Hz, random phase per trial), slow drift and noise.
%   Amplitude   amplitude(animal, condition) = trueMeans(condition)
%               + animal effect (SD animalSD = 3 PU, shared by the
%               conditions) + animal-by-condition scatter (SD withinSD =
%               2.5 PU); each of the 8 trials adds jitter (SD trialSD = 2).
%               trueMeans = [18 30 24] PU (Control, Stimulated, Drug).
%               Population effects: Stimulated - Control = 12 PU, d_z =
%               3.27 (paired), Cohen's d = 3.02 (unpaired), ANOVA eta^2 =
%               0.60; the paired test and the ANOVA are significant with
%               near certainty for 8 animals.
%
% Output struct demo:
%   folder, conditions (1x3 cellstr), paths (1x3 cell, each 8x1 cellstr
%   of file paths in animal order), files (struct array: path, condition,
%   animal), truth:
%     meanAmplitude [18 30 24], peakDelay 4, animalSD, withinSD,
%     trialSD, nAnimals, nTrials, amplitude (8x3, realized mean response
%     per file = what a perfect peak-amplitude measurement would give),
%     effect.meanDiff (Stimulated - Control, population: 12 PU),
%     effect.dz (population d_z of the file amplitudes), effect.d
%     (population Cohen's d, ignoring the pairing), effect.sampleDz and
%     effect.sampleD (the same computed from truth.amplitude), and
%     anovaEta2 (population eta^2 of the three conditions).
% =========================================================================

function demo = demoGroups(folder)
    if nargin < 1 || isempty(folder)
        folder = fullfile(tempdir, 'NeuroAnalyzerDemo', 'groups');
    end
    if ~exist(folder, 'dir'), mkdir(folder); end

    rs = RandStream('mt19937ar', 'Seed', 20260925);
    conditions = {'Control', 'Stimulated', 'Drug'};
    trueMeans = [18 30 24];
    nAnimals = 8; nTrials = 8;
    animalSD = 3; withinSD = 2.5; trialSD = 2;
    Fs = 10; t = -5:1/Fs:20;
    tp = 4; a = 3;                       % gamma shape: peak at tp seconds
    x = t / tp;
    shape = zeros(size(t));
    on = x > 0;
    shape(on) = x(on).^a .* exp(a * (1 - x(on)));

    animalEffect = animalSD * randn(rs, nAnimals, 1);
    baseline = 110 + 20 * rand(rs, nAnimals, 1);
    amp = repmat(trueMeans, nAnimals, 1) + repmat(animalEffect, 1, 3) + ...
        withinSD * randn(rs, nAnimals, 3);

    nC = numel(conditions);
    paths = cell(1, nC);
    files = struct('path', {}, 'condition', {}, 'animal', {});
    realized = zeros(nAnimals, nC);
    for c = 1:nC
        paths{c} = cell(nAnimals, 1);
        for k = 1:nAnimals
            seg = zeros(nTrials, numel(t));
            trialAmp = amp(k, c) + trialSD * randn(rs, nTrials, 1);
            for j = 1:nTrials
                phase = 2 * pi * rand(rs);
                seg(j, :) = baseline(k) + 1.5 * sin(2 * pi * t / 60 + phase) ...
                    + 3 * sin(2 * pi * 0.13 * t + phase) ...
                    + trialAmp(j) * shape + 0.5 * randn(rs, size(t));
            end
            realized(k, c) = mean(trialAmp);
            s = struct();
            s.segmentedLDF = seg;
            s.segmentedTime = t;
            s.Fs = Fs;
            s.truth = struct('condition', conditions{c}, 'animal', k, ...
                'amplitude', realized(k, c), 'responsePeakDelay', tp, 'baseline', baseline(k));
            p = fullfile(folder, sprintf('%s_animal%02d.mat', lower(conditions{c}), k));
            save(p, '-struct', 's');
            paths{c}{k} = p;
            files(end + 1) = struct('path', p, 'condition', conditions{c}, 'animal', k); %#ok<AGROW>
        end
    end

    % Population truth for the file-level amplitudes (mean of nTrials trials)
    varFile = withinSD^2 + trialSD^2 / nTrials;          % around animal mean
    meanDiff = trueMeans(2) - trueMeans(1);
    effect = struct('meanDiff', meanDiff, ...
        'dz', meanDiff / sqrt(2 * varFile), ...
        'd', meanDiff / sqrt(animalSD^2 + varFile), ...
        'sampleDz', mean(realized(:, 2) - realized(:, 1)) / std(realized(:, 2) - realized(:, 1)), ...
        'sampleD', (mean(realized(:, 2)) - mean(realized(:, 1))) / ...
            sqrt((var(realized(:, 1)) + var(realized(:, 2))) / 2));
    varBetween = mean((trueMeans - mean(trueMeans)).^2);
    truth = struct('meanAmplitude', trueMeans, 'peakDelay', tp, 'animalSD', animalSD, ...
        'withinSD', withinSD, 'trialSD', trialSD, 'nAnimals', nAnimals, 'nTrials', nTrials, ...
        'amplitude', realized, 'effect', effect, ...
        'anovaEta2', varBetween / (varBetween + animalSD^2 + varFile));
    truth.conditions = conditions;

    demo = struct('folder', folder, 'conditions', {conditions}, 'paths', {paths}, ...
        'files', files, 'truth', truth);
end
