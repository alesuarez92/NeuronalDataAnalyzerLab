%% MethodsWriterTest.m
% =========================================================================
% METHODS TEXT (core/MethodsWriter) FROM SESSIONS BUILT ON DEMO DATA
% =========================================================================
% Headless (no windows): sessions are built like the windows'
% sessionState() from analyses run on DemoData with the same core code the
% windows use, then turned into methods text. The tests check that:
%   - LDF processing (decimate x10, 1 Hz low-pass, -5 to 20 s trials): the
%     text has the factor, both rates, cut-off, filter order, trial window
%     and the number of trials of the actual run;
%   - LFP ERP + kCSD: epoch window, epochs used, spacing, the R and
%     lambda chosen by cross-validation, and Potworowski et al. (2012) in
%     the text and the reference list (and no iCSD reference);
%   - repeated-measures ANOVA: Mauchly, Greenhouse-Geisser, Holm and
%     Friedman cited, groups with their n, the sphericity outcome;
%   - every text names Neuronal Data Analyzer Lab v<version> and the MATLAB release,
%     and never contains NaN, Inf, [], unresolved {{citations}}, &entities;
%     or sprintf specifiers (%d, %s, %g ...), or an empty placeholder;
%   - histology (demo-like session): images, pixel size, alignment, the
%     counting settings in um, Otsu (1979) cited only for the automatic
%     threshold, markers and regions;
%   - laser speckle (the demo analysed headless): image size, exposure,
%     dark level, window, frames averaged, flow index, ROIs, trials and
%     the response window; Briers & Webster / Boas & Dunn cited, the
%     exposure model (Bandyopadhyay et al.) only when used;
%   - EEG analysis (demo-like session): participants, EEGLAB cited, the
%     history read from the files, baseline, the measure and the
%     repeated-measures test on it; a continuous recording's epochs; the
%     electrode layout once confirmed (from the files, by name on the 10-5
%     system with Oostenveld & Praamstra / Jurcak et al. cited, a
%     positions file with its format, mm from bregma; old names T3 / T4,
%     channels without a position);
%   - several sessions given in any order come out in pipeline order,
%     with one placeholder, one software paragraph and one reference list;
%   - write() saves UTF-8 with a byte-order mark; a saved session file
%     gives the same text; bad input raises NeuroAnalyzer:MethodsWriter:*.
% With a display: the Methods text dialog opens with the text.
% =========================================================================

function tests = MethodsWriterTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

%% ------------------------------------------------------------- windows

function testLDFProcessing(tests)
    [s, r] = ldfProcessingSession(tests);
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'decimated by a factor of 10');
    verifyHas(tests, txt, sprintf('from %d to %d Hz', 1000, 100));
    verifyHas(tests, txt, 'low-pass filtered at 1 Hz');
    verifyHas(tests, txt, '4th-order Butterworth filter');
    verifyHas(tests, txt, 'zero phase');
    verifyHas(tests, txt, 'from 5 s before to 20 s after each onset');
    verifyHas(tests, txt, sprintf('(n = %d trials)', r.nTrials));
    verifyHas(tests, txt, 'above 0.5');
    verifyHas(tests, txt, 'Signal Processing Toolbox');
    tests.verifyEqual(numel(refs), 1, 'Only the Neuronal Data Analyzer Lab reference');
    verifyHas(tests, refs{1}, sprintf('version %s', UITheme.version));
end

function testLFPERPAndKCSD(tests)
    [s, erp, info] = lfpKCSDSession();
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'from 50 ms before to 200 ms after each onset');
    verifyHas(tests, txt, sprintf('n = %d of %d epochs', erp.nValid, numel(erp.onsetTimes)));
    verifyHas(tests, txt, 'channels 1');
    verifyHas(tests, txt, ['inter-contact spacing 100 ' char(181) 'm']);
    verifyHas(tests, txt, 'kernel CSD (kCSD; Potworowski et al., 2012)');
    verifyHas(tests, txt, sprintf('%d Gaussian basis sources', info.nSources));
    verifyHas(tests, txt, sprintf('R (%s %sm)', MethodsWriter.num(info.R), char(181)));
    verifyHas(tests, txt, 'leave-one-out cross-validation');
    verifyHas(tests, txt, 'conductivity 0.3 S/m');
    verifyHas(tests, txt, ['A/m' char(179)]);
    verifyHas(tests, txt, 'Welch''s method (Welch, 1967');
    tests.verifyTrue(any(contains(refs, 'Kernel current source density method')), 'kCSD reference');
    tests.verifyTrue(any(contains(refs, 'Neural Comput 24(2):541')), 'kCSD journal');
    tests.verifyFalse(any(contains(refs, 'Pettersen')), 'No iCSD reference for kCSD');
    % The standard CSD of the same session cites Nicholson & Freeman / Mitzdorf instead
    s.settings.csd.usedMethod = 'standard';
    [txt2, refs2] = MethodsWriter.fromSession(s);
    checkClean(tests, txt2, refs2);
    verifyHas(tests, txt2, 'negative second spatial derivative');
    tests.verifyTrue(any(contains(refs2, 'Mitzdorf U (1985)')));
    tests.verifyTrue(any(contains(refs2, 'Nicholson C, Freeman JA (1975)')));
    tests.verifyFalse(any(contains(refs2, 'Potworowski')));
end

function testRepeatedMeasuresStats(tests)
    [s, res] = rmStatsSession();
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'repeated-measures ANOVA');
    verifyHas(tests, txt, 'Control (n = 8), Stimulated (n = 8) and Drug (n = 8)');
    verifyHas(tests, txt, 'Mauchly''s test (Mauchly, 1940)');
    verifyHas(tests, txt, ['Greenhouse' char(8211) 'Geisser correction (Greenhouse & Geisser, 1959)']);
    verifyHas(tests, txt, 'Holm-adjusted p-values (Holm, 1979)');
    verifyHas(tests, txt, 'The Friedman test (Friedman, 1937) was run as a robustness check');
    verifyHas(tests, txt, sprintf('W = %s', MethodsWriter.num(res.main.sphericity.W)));
    verifyHas(tests, txt, 'peak amplitude relative to baseline');
    for key = {'Mauchly JW (1940)', 'Greenhouse SW, Geisser S (1959)', 'Holm S (1979)', 'Friedman M (1937)', ...
            'Huynh H, Feldt LS (1976)', 'Olejnik S, Algina J (2003)', 'Bakeman R (2005)'}
        tests.verifyTrue(any(contains(refs, key{1})), key{1});
    end
    tests.verifyEqual(refs, sort(refs), 'References in alphabetical order');
    % Rank-based choice: Friedman first, no sphericity sentence
    s.results.groupTest = GroupStats.compare(res.values, res.groupNames, 'rm', 'nonparametric');
    txt2 = MethodsWriter.fromSession(s);
    verifyHas(tests, txt2, 'compared with the Friedman test (Friedman, 1937');
    tests.verifyFalse(contains(txt2, 'In these data, Mauchly'));
end

function testCombinedPipelineOrder(tests)
    e = Session.new('ExtractLDFApp');
    e.settings = struct('range', [20 280], 'view', 'Cropped segment', 'stimulusChannel', 6, 'ldfChannel', 8);
    e.results = struct('cropRange', [20 280], 'fs', 1000, 'nSamples', 260001, 'ldfMean', 120, 'ldfSD', 4);
    e.summary = {'Recording: 300000 samples at 1000 Hz (5 min)'};
    p = ldfProcessingSession(tests);
    g = Session.new('LDFGrandAverageApp');
    g.inputs = [Session.fileInfo('', 'Trial file 1'), Session.fileInfo('', 'Trial file 2')];
    g.settings = struct('relativeToBaseline', true, 'grandAverageShown', true);
    g.results = struct('nTrials', 16, 'fileCounts', [8 8], 'window', [-5 20], 'nSamples', 251);
    sc = rmStatsSession();
    % Given out of order (and one twice): pipeline order, duplicates once
    [txt, refs] = MethodsWriter.fromSessions({sc, g, p, e, g});
    checkClean(tests, txt, refs);
    idx = [strfind(txt, 'LabChart'), strfind(txt, 'decimated by a factor'), ...
        strfind(txt, 'were pooled'), strfind(txt, 'repeated-measures ANOVA')];
    tests.verifyNumElements(idx, 4, 'Every step described once');
    tests.verifyTrue(issorted(idx), 'Steps in pipeline order: Extract, Process, Average, Statistics');
    tests.verifyEqual(numel(strfind(txt, 'were pooled')), 1, 'Duplicate session described once');
    tests.verifyTrue(startsWith(txt, '[Describe the animals'), 'Placeholder first');
    tests.verifyEqual(numel(strfind(txt, '[Describe the animals')), 1);
    tests.verifyEqual(numel(strfind(txt, 'Analyses were performed with Neuronal Data Analyzer Lab')), 1);
    tests.verifyGreaterThan(strfind(txt, 'Analyses were performed with Neuronal Data Analyzer Lab'), idx(end), 'Software last');
    tests.verifyEqual(numel(refs), numel(unique(refs)), 'One reference list without duplicates');
    % Paths work too
    f1 = Session.save(fullfile(tests.TestData.dir, 'e'), e);
    f2 = Session.save(fullfile(tests.TestData.dir, 'p'), p);
    tests.verifyEqual(MethodsWriter.fromSessions({f2, f1}), MethodsWriter.fromSessions({e, p}));
end

function testExtractLDFFormats(tests)
    % Sessions with the recording format and channel names
    e = Session.new('ExtractLDFApp');
    e.settings = struct('range', [0 60], 'view', 'Cropped segment', 'format', 'acqmat', ...
        'flowChannel', 2, 'flowName', 'LDF100C', 'flowUnits', 'BPU', 'stimulus', 1, ...
        'stimName', 'Trigger', 'block', 1, 'stimulusChannel', 1, 'ldfChannel', 2, 'rate', 500);
    e.results = struct('cropRange', [0 60], 'fs', 500, 'nSamples', 30001, 'ldfMean', 120, 'ldfSD', 4);
    [txt, refs] = MethodsWriter.fromSession(e);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'probe] with AcqKnowledge (BIOPAC) and exported as a .mat file (LDF on');
    verifyHas(tests, txt, 'LDF on channel 2 ("LDF100C", BPU) and stimulus trigger on channel 1 ("Trigger"), both sampled at 500 Hz');
    tests.verifyFalse(contains(txt, 'LabChart'));
    % Comments as the stimulus, block 2 of a LabChart file
    e.settings.format = 'labchart';
    e.settings.stimulus = 'events:Puff';
    e.settings.block = 2;
    e.settings.flowUnits = '';
    txt = MethodsWriter.fromSession(e);
    verifyHas(tests, txt, 'with LabChart (ADInstruments) and exported as a .mat file');
    verifyHas(tests, txt, 'LDF on channel 2 ("LDF100C"), stimulus onsets from the comments "Puff" and block 2 of the recording, LDF sampled at 500 Hz');
    % No stimulus, text table
    e.settings.format = 'text';
    e.settings.stimulus = 0;
    e.settings.block = 1;
    txt = MethodsWriter.fromSession(e);
    verifyHas(tests, txt, 'exported as a text table (LDF on channel 2 ("LDF100C") and no stimulus channel, LDF sampled at 500 Hz)');
    e.settings.formatLabel = 'LabChart text export';
    txt = MethodsWriter.fromSession(e);
    verifyHas(tests, txt, 'with LabChart (ADInstruments) and exported as a text file (LDF on');
end

function testExtractEphysFormats(tests)
    % The recording format named in the first sentence
    e = Session.new('ExtractEphysApp');
    names = {'intanrhs', 'Intan RHS2000 data file (.rhs)'; 'neuralynx', 'Neuralynx continuous sampled channel (.ncs) files'; ...
        'openephyslegacy', 'Open Ephys data format (.continuous) files'};
    for k = 1:size(names, 1)
        e.settings = struct('format', names{k, 1});
        [txt, refs] = MethodsWriter.fromSession(e);
        checkClean(tests, txt, refs);
        verifyHas(tests, txt, ['acquisition system] and read from the ' names{k, 2}]);
    end
end

function testHistology(tests)
    s = histologySession();
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['2 images (400 ' char(215) ' 400 pixels, 2 channels: Nuclei (DAPI) and Marker (GFP))']);
    verifyHas(tests, txt, [' at 1 ' char(181) 'm per pixel (read from the image files)']);
    verifyHas(tests, txt, 'shifted onto the first by the peak of their FFT cross-correlation');
    verifyHas(tests, txt, 'Nuclei (DAPI) channel (largest shift 11.2 pixels)');
    verifyHas(tests, txt, 'Cells were counted in the Nuclei (DAPI) channel');
    verifyHas(tests, txt, ['square of side twice 15 ' char(181) 'm']);
    verifyHas(tests, txt, 'with Otsu''s method (Otsu, 1979)');
    verifyHas(tests, txt, ['smaller than 20 ' char(181) 'm' char(178) ', larger than 2000 ']);
    verifyHas(tests, txt, 'ratio above 2.5');
    verifyHas(tests, txt, 'at least 50% of its pixels');
    verifyHas(tests, txt, '2 regions drawn by hand on the first image (Region A and Region B)');
    tests.verifyTrue(any(contains(refs, 'Otsu N (1979)')), 'Otsu reference');
    % Landmark alignment, typed threshold, no regions, not counted yet
    s.settings.alignedMethod = 'landmarks'; s.settings.channelsAligned = false;
    s.results.landmarkRms = [NaN 1.23];
    s.settings.count.threshold = 0.2; s.settings.regions = struct('name', {}, 'xy', {});
    [txt2, refs2] = MethodsWriter.fromSession(s);
    checkClean(tests, txt2, refs2);
    verifyHas(tests, txt2, 'affine transform fitted by least squares');
    verifyHas(tests, txt2, 'at most 1.2 pixels');
    verifyHas(tests, txt2, 'thresholded at 0.2 (intensity above background)');
    verifyHas(tests, txt2, ['cells per mm' char(178) ' of image area']);
    tests.verifyFalse(any(contains(refs2, 'Otsu')), 'No Otsu reference for a typed threshold');
    s.results = rmfield(s.results, 'counts');
    txt3 = MethodsWriter.fromSession(s);
    tests.verifyFalse(contains(txt3, 'Cells were counted'), 'No counting text before counting');
end

function testLaserSpeckle(tests)
    % A session as LSCIAnalysisApp.sessionState builds it, from the demo analysed headless
    d = demoLSCI(struct('Seconds', 40));
    p = LaserSpeckle.defaults();
    p.Dark = d.dark; p.Fps = d.fps; p.ExposureMs = d.exposureMs; p.Frames = 5;
    p.Onsets = LaserSpeckle.onsetsFromStimulus(d.stim, d.t, 1);
    R = LaserSpeckle.analyze(d.frames, d.t, d.roiMasks, p);
    s = Session.new('LSCIAnalysisApp');
    s.settings.params = p;
    s.summary = {sprintf('Images: %d x %d px, %d frames (raw); 3 ROI(s)', size(d.frames, 2), size(d.frames, 1), ...
        size(d.frames, 3))};
    s.results = struct('fps', R.fps, 'roiNames', {d.roiNames}, 'onsets', R.onsets, 'response', R.response);
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Laser speckle images (80 ' char(215) ' 64 pixels, 400 frames) were acquired with an ' ...
        'exposure time of 5 ms']);
    verifyHas(tests, txt, 'A camera dark level of 100 counts was subtracted');
    verifyHas(tests, txt, ['sliding 7 ' char(215) ' 7 pixel window in every frame (Briers & Webster, 1996; Boas & Dunn, 2010)']);
    verifyHas(tests, txt, 'averaged over non-overlapping blocks of 5 frames');
    verifyHas(tests, txt, ['speckle flow index 1/K' char(178)]);
    verifyHas(tests, txt, '3 regions of interest (Activated area, Control cortex and Vessel) at 2 values per second');
    verifyHas(tests, txt, 'For the stimulus, a trial from 5 s before to 15 s after onset');   % 40 s: one trial fits
    verifyHas(tests, txt, 'the mean change 2 to 6 s after onset');
    tests.verifyTrue(any(contains(refs, 'Briers JD, Webster S (1996)')));
    tests.verifyFalse(any(contains(refs, 'Bandyopadhyay')), 'model not used: not cited');
    % The exposure model, temporal contrast, and exported perfusion images
    s.settings.params.FlowModel = 'tauc'; s.settings.params.Beta = 0.8;
    s.settings.params.Contrast = 'temporal'; s.settings.params.Frames = 25;
    [txt2, refs2] = MethodsWriter.fromSession(s);
    checkClean(tests, txt2, refs2);
    verifyHas(tests, txt2, 'over non-overlapping blocks of 25 consecutive frames (Cheng et al., 2003)');
    verifyHas(tests, txt2, ['inverse decorrelation time 1/' char(964) 'c']);
    verifyHas(tests, txt2, ['with T = 5 ms and ' char(946) ' = 0.8']);
    tests.verifyTrue(any(contains(refs2, 'Bandyopadhyay R')));
    s.settings.params.InputType = 'flow';
    txt3 = MethodsWriter.fromSession(s);
    verifyHas(tests, txt3, 'Perfusion images (80');
    tests.verifyFalse(contains(txt3, 'speckle contrast K'), 'no contrast step for exported perfusion images');
end

%% ---------------------------------------------------------- core / files

function testWriteUTF8(tests)
    [s] = lfpKCSDSession();
    [txt, refs] = MethodsWriter.fromSession(s);
    out = MethodsWriter.write(fullfile(tests.TestData.dir, 'methods'), txt, refs);
    tests.verifyTrue(endsWith(out, 'methods.txt'));
    fid = fopen(out, 'r');
    b = fread(fid, Inf, '*uint8')';
    fclose(fid);
    tests.verifyEqual(b(1:3), uint8([239 187 191]), 'UTF-8 byte-order mark');
    back = native2unicode(b(4:end), 'UTF-8');
    back = strrep(back, sprintf('\r\n'), newline);
    tests.verifyEqual(back, MethodsWriter.compose(txt, refs));
    verifyHas(tests, back, [newline newline 'References' newline]);
    verifyHas(tests, back, char(181));   % micro sign survived the round trip
end

function testEEGAnalysis(tests)
    [s, res] = eegSession();
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'EEG was recorded from 8 participants [please add: recording system');
    verifyHas(tests, txt, 'cleaned in EEGLAB (Delorme & Makeig, 2004) before the analysis');
    verifyHas(tests, txt, 'The data comprised 32 channels at 250 Hz, referenced to the average of all channels.');
    verifyHas(tests, txt, ['The data files recorded these earlier processing steps: Band-pass filtered 0.1 to 30 Hz ' ...
        '(pop_eegfiltnew); Re-referenced to the average of all channels (pop_reref).']);
    verifyHas(tests, txt, 'Standard (320 trials), Target (120 trials) and Novel (80 trials) in total');
    verifyHas(tests, txt, ['after subtracting from every trial and channel its mean from ' char(8722) '200 to 0 ms']);
    verifyHas(tests, txt, 'each participant weighted equally');
    verifyHas(tests, txt, 'the mean amplitude from 300 to 400 ms at Pz was measured.');
    verifyHas(tests, txt, ['The mean amplitude from 300 to 400 ms at Pz was compared between Standard (n = 8), ' ...
        'Target (n = 8) and Novel (n = 8), using one value per participant and condition, with participants ' ...
        'matched across conditions.']);
    verifyHas(tests, txt, 'one-way repeated-measures ANOVA');
    tests.verifyTrue(any(startsWith(refs, 'Delorme A, Makeig S (2004). EEGLAB')));
    tests.verifyFalse(any(startsWith(refs, 'Oostenveld')), 'FieldTrip not used, not cited');
    tests.verifyTrue(res.main.p < 0.05);
    tests.verifyFalse(contains(txt, 'Scalp maps'), 'no scalp maps drawn, none described');

    % Scalp maps: spherical splines on the head; a flat map between skull electrodes
    m = eegSession();
    m.settings.scalpMaps = struct('window', [0.3 0.4], 'participant', 'All participants (grand average)', ...
        'condA', 'Target', 'condB', 'Standard');
    m.results.scalpMaps = struct('names', {{'Standard', 'Target', 'Novel', 'Target minus Standard'}}, ...
        'kind', 'scalp', 'method', 'spherical spline', 'electrodes', {{'Fp1', 'Fp2'}}, 'left', {{}});
    [txt, refs] = MethodsWriter.fromSession(m);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Scalp maps of the mean voltage from 300 to 400 ms were interpolated over the head with ' ...
        'spherical splines (Perrin et al., 1989; order m = 4, 50 Legendre terms, no regularization).']);
    tests.verifyTrue(any(startsWith(refs, 'Perrin F, Pernier J, Bertrand O, Echallier JF (1989)')));
    m.settings.scalpMaps.window = [0.05 0.05];
    m.results.scalpMaps.kind = 'skull';
    [txt, refs] = MethodsWriter.fromSession(m);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Maps of the voltage at 50 ms were interpolated between the skull electrodes with a ' ...
        'thin-plate spline (Duchon, 1977) and drawn only within their outline.']);
    tests.verifyTrue(any(startsWith(refs, 'Duchon J (1977)')));
    tests.verifyFalse(any(startsWith(refs, 'Perrin')), 'no spherical splines, not cited');

    % Peak measure, FieldTrip, continuous recordings cut into trials, no baseline, no test
    s.settings.sources = repmat({'FieldTrip'}, 1, 8);
    s.settings.trialWindow = [-0.1 0.4];
    s.settings.baselineOn = false;
    s.settings.measure = struct('Measure', 'peak', 'Polarity', 'negative', 'Window', [0.03 0.07], ...
        'Channels', {{'V1-L', 'V1-R'}});
    s.results = rmfield(s.results, 'groupTest');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'cleaned in FieldTrip (Oostenveld et al., 2011)');
    verifyHas(tests, txt, ['cut into epochs from ' char(8722) '100 to 400 ms around each event']);
    verifyHas(tests, txt, 'without further baseline correction');
    verifyHas(tests, txt, ['the negative peak amplitude from 30 to 70 ms averaged over V1-L and V1-R was measured ' ...
        'as the most negative value']);
    tests.verifyFalse(contains(txt, 'was compared between'), 'no test run, none described');

    % Pipeline order: EEG Analysis before Signal Characterization
    txt = MethodsWriter.fromSessions({rmStatsSession(), eegSession()});
    tests.verifyLessThan(strfind(txt, 'EEG was recorded'), strfind(txt, 'Control (n = 8)'));
end

function testSessionFileAndErrors(tests)
    s = rmStatsSession();
    f = Session.save(fullfile(tests.TestData.dir, 'stats'), s);
    [a, ra] = MethodsWriter.fromSession(s);
    [b, rb] = MethodsWriter.fromSession(f);
    tests.verifyEqual(b, a);
    tests.verifyEqual(rb, ra);
    tests.verifyError(@() MethodsWriter.fromSessions({}), 'NeuroAnalyzer:MethodsWriter:noSessions');
    tests.verifyError(@() MethodsWriter.fromSession(struct('x', 1)), 'NeuroAnalyzer:MethodsWriter:invalidSession');
    tests.verifyError(@() MethodsWriter.fromSession(42), 'NeuroAnalyzer:MethodsWriter:invalidSession');
end

function testEmptyAndUnknownSessions(tests)
    s = Session.new('LFPAnalysisApp');   % saved before any analysis
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, '[please add: the LFPAnalysisApp session holds no analysis yet');
    u = Session.new('SomeFutureApp');
    u.appTitle = 'Future window';
    txt = MethodsWriter.fromSession(u);
    verifyHas(tests, txt, '[please add: describe the analysis done in Future window.]');
    % Missing values are left out, never invented
    p = Session.new('ProcessingLDFApp');
    p.settings = struct('processing', struct('downsample', 1, 'filterType', 2, 'designType', 1, ...
        'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', 1), 'segmented', false);
    [txt, refs] = MethodsWriter.fromSession(p);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, 'LDF signals were low-pass filtered at 1 Hz');
    tests.verifyFalse(contains(txt, 'Trials were cut'));
end

function testTextHelpers(tests)
    tests.verifyEqual(MethodsWriter.num(24414.0625), '24414.06');
    tests.verifyEqual(MethodsWriter.num(0.3), '0.3');
    tests.verifyEqual(MethodsWriter.num(8), '8');
    tests.verifyEqual(MethodsWriter.entities(MethodsWriter.num(-5)), [char(8722) '5']);
    tests.verifyEqual(MethodsWriter.dur(0.05), '50 ms');
    tests.verifyEqual(MethodsWriter.dur(20), '20 s');
    tests.verifyEqual(MethodsWriter.ordinal(4), '4th');
    tests.verifyEqual(MethodsWriter.ordinal(22), '22nd');
    tests.verifyEqual(MethodsWriter.ordinal(12), '12th');
    tests.verifyEqual(MethodsWriter.listText({'a', 'b', 'c'}), 'a, b and c');
    tests.verifyEqual(MethodsWriter.entities(MethodsWriter.chanText(1:8)), ['channels 1' char(8211) '8']);
    tests.verifyEqual(MethodsWriter.chanText([4 5]), 'channels 4 and 5');
    tests.verifyEqual(MethodsWriter.releaseText(struct('matlabRelease', '', ...
        'matlabVersion', '9.10.0.1602886 (R2021a)')), 'R2021a');
end

%% ----------------------------------------------------------------- UI

function testDialog(tests)
    assumeDisplay(tests);
    s = lfpKCSDSession();
    fig = MethodsWriter.dialog([], {s});
    c = onCleanup(@() delete(fig));
    ta = findobj(fig, 'Type', 'uitextarea');
    tests.verifyNumElements(ta, 1);
    shown = MethodsWriter.dialogText(fig);
    [txt, refs] = MethodsWriter.fromSession(s);
    % The text area has no empty lines: one line per paragraph
    tests.verifyEqual(shown, regexprep(MethodsWriter.compose(txt, refs), '\n(\s*\n)+', '\n'));
    lbl = findobj(fig, 'Type', 'uilabel');
    tests.verifyTrue(any(contains(strjoin(cellfun(@char, {lbl.Text}, 'UniformOutput', false), ' '), ...
        MethodsWriter.CheckNote)), 'Check note shown');
    btn = findobj(fig, 'Type', 'uibutton');
    labels = {btn.Text};
    for want = {['Add saved sessions' char(8230)], 'Copy', ['Save .txt' char(8230)], 'Close'}
        tests.verifyTrue(any(strcmp(labels, want{1})), want{1});
    end
end

%% ------------------------------------------------------------- helpers

%% ldfProcessingSession - ProcessingLDFApp session of the demo: x10, 1 Hz low-pass, -5..20 s
function [s, r] = ldfProcessingSession(tests)
    tests.assumeTrue(exist('decimate', 'file') == 2 && exist('butter', 'file') == 2, ...
        'LDF processing needs the Signal Processing Toolbox');
    d = DemoData.ldfCropped();
    proc = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    p = proc;
    p.threshold = 0.5; p.preSec = 5; p.postSec = 20; p.minISI = 1;
    r = LDFPipeline.run(d.LDF, d.stim, d.t, d.Fs, p);
    s = Session.new('ProcessingLDFApp');
    s.appTitle = 'LDF Processing';
    s.settings = struct('processing', proc, 'threshold', 0.5, 'preS', 5, 'postS', 20, 'minISI', 1, ...
        'segmented', true, 'tab', 'Trials');
    s.results = struct('nTrials', r.nTrials, 'window', r.segmentedTime([1 end]), 'fs', r.Fs, ...
        'mean', mean(r.segmentedLDF, 1), 'sd', std(r.segmentedLDF, 0, 1));
    s.summary = {sprintf('Loaded %d samples at %g Hz; processed rate %g Hz', numel(d.LDF), d.Fs, r.Fs)};
end

%% lfpKCSDSession - LFPAnalysisApp session of the demo: ERP (-50..200 ms), kCSD, Welch spectrum
function [s, erp, info] = lfpKCSDSession()
    d = DemoData.lfpFile();
    prm = struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5);
    ch = 1:size(d.lfp_data, 1);
    onsets = ERPAnalysis.detectOnsets(d.stim_data, d.stim_fs, prm.threshold, prm.minISI);
    [avg, sd, t, nValid] = ERPAnalysis.average(d.lfp_data(ch, :), d.lfp_fs, onsets, prm.preTime, prm.postTime);
    csdPrm = struct('sigma', 0.3, 'diameterUm', 500, 'smoothUm', 0, 'RUm', 0, 'lambda', 0);
    [csd, info] = CSDMethods.estimate(avg, (0:numel(ch) - 1) * 100, 'kcsd', ...
        struct('sigma', 0.3, 'diameterUm', 500, 'smoothUm', 0));
    erp = struct('mean', avg, 'sd', sd, 't', t, 'nValid', nValid, 'onsetTimes', onsets, 'channels', ch);
    [pxx, f] = TimeFrequency.welchPSD(d.lfp_data(4, :), d.lfp_fs, 2, 0.5);
    s = Session.new('LFPAnalysisApp');
    s.appTitle = 'LFP Analysis';
    s.settings.channels = ch;
    s.settings.erp = struct('params', prm, 'channels', ch);
    s.settings.csd = struct('spacingUm', 100, 'order', num2str(ch), 'computed', true, 'usedOrder', ch, ...
        'usedSpacingUm', 100, 'method', 'kcsd', 'params', csdPrm, 'usedMethod', 'kcsd', 'usedParams', csdPrm);
    s.settings.tfRuns = struct('spectrum', struct('channel', 4), 'spectrogram', [], 'ersp', [], 'bandpower', []);
    s.results.erp = erp;
    s.results.csd = struct('csd', csd, 'order', ch, 'spacingUm', 100, 'method', 'kcsd', 'params', csdPrm, 'info', info);
    s.results.spectrum = struct('channel', 4, 'f', f, 'pxx', pxx, 'segSec', 2);
    s.summary = {sprintf('LFP: %d channels at %.2f Hz, %.1f s', size(d.lfp_data, 1), d.lfp_fs, ...
        size(d.lfp_data, 2) / d.lfp_fs)};
end

%% rmStatsSession - SignalCharacterizationApp session: rm-ANOVA on 8 animals x 3 conditions
function [s, res] = rmStatsSession()
    Y = [18 30 24; 17 31 25; 19 29 23; 18.5 30.5 26; 17.2 28 22; 18.8 33 24.5; 16 29 23; 20 32 25];
    names = {'Control', 'Stimulated', 'Drug'};
    res = GroupStats.compare(num2cell(Y, 1), names, 'rm', 'parametric');
    s = Session.new('SignalCharacterizationApp');
    s.appTitle = 'Signal Characterization';
    sg = struct('input', 0, 'dataType', 'Time series (t, y)', 't0', 0, 'baseline', [-5 0], ...
        'direction', 'Auto', 'features', {{'Peak amplitude'}}, 'series', 1, 'extracted', false);
    gs = struct('files', struct('group', {}, 'input', {}), 'order', {names}, 'groupName', 'Drug', ...
        'feature', 'Peak amplitude', 'subjectMode', 'File (mean trace)', 't0', 0, 'baseline', [-5 0], ...
        'baselineAuto', true, 'direction', 'Positive', ...
        'design', 'Repeated measures (same animals, 3+ conditions)', 'method', 'Parametric', ...
        'groupA', 'Control', 'groupB', 'Stimulated', 'plotStyle', ['Mean ' char(177) ' SEM'], 'tested', true);
    s.settings = struct('mode', 'Groups & statistics', 'single', sg, 'groups', gs);
    s.results.groupTest = res;
    s.summary = {sprintf('Group test: %s', res.summary)};
end

%% testEEGTimeFrequency - Morlet ERSP / ITPC and band power of the EEG window (step 7)
function testEEGTimeFrequency(tests)
    [s, ~] = eegSession();
    tests.verifyFalse(contains(MethodsWriter.fromSession(s), 'Morlet'), 'no time-frequency, none described');
    s.settings.tfShown = true;
    s.settings.timeFrequency = struct('frequencies', [4 40], 'cycles', 3, 'baseline', [-0.2 0], ...
        'channels', {{'Oz'}}, 'channelsTyped', {{'Oz'}}, 'band', [8 13], 'bandName', 'Alpha');
    s.results.timeFrequency = struct('conditions', {{'Standard', 'Target', 'Novel'}}, 'trials', [288 112 120], ...
        'participants', 8, 'freqs', 4:40, 'cycles', 3 * ones(1, 37), 'baseline', [-0.2 0], 'channels', {{'Oz'}}, ...
        'band', [8 13], 'bandName', 'Alpha', 'lowestWithValues', 4, 'lowestWithBaseline', 8, 'text', '');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Time' char(8211) 'frequency representations were computed for every trial at Oz from ' ...
        'complex Morlet wavelet transforms (3 cycles; 37 frequencies from 4 to 40 Hz; wavelets truncated at ' ...
        char(177) '3 standard deviations']);
    verifyHas(tests, txt, ['(ERSP; Makeig, 1993) was expressed in dB relative to the mean power of each condition ' ...
        'from ' char(8722) '200 to 0 ms (from 8 Hz up, where whole wavelets fitted within that window)']);
    verifyHas(tests, txt, '(ITPC; Tallon-Baudry et al., 1996)');
    verifyHas(tests, txt, ['alpha band power (8' char(8211) '13 Hz; the mean wavelet power over its frequencies)']);
    verifyHas(tests, txt, 'Pfurtscheller & Lopes da Silva, 1999');
    verifyHas(tests, txt, 'Grand averages were the means of the participants'' ERSP (in dB), ITPC and band power');
    tests.verifyTrue(any(startsWith(refs, 'Makeig S (1993)')));
    tests.verifyTrue(any(startsWith(refs, 'Tallon-Baudry C')));
    % Without ERPs (the time-frequency alone) it is still described
    s.settings.erpsShown = false;
    verifyHas(tests, MethodsWriter.fromSession(s), 'complex Morlet wavelet transforms');
    % Two channels
    s.results.timeFrequency.channels = {'O1', 'O2'};
    verifyHas(tests, MethodsWriter.fromSession(s), 'at O1 and O2 (power and phase locking averaged over channels)');
end

function testEEGAnalysisCleaning(tests)
    % Raw recordings cleaned in the EEG window: bad channel, filters, re-reference, events, rejection
    s = eegSession();
    s.settings.generator = 'demoEEGraw';
    s.settings.participants = {'sub-01', 'sub-02', 'sub-03'};
    s.settings.sources = repmat({'BrainVision Recorder'}, 1, 3);
    s.settings.reference = 'average of the 31 good channels (T7 marked bad and left out)';
    s.settings.recordedReference = 'channel FCz';
    s.settings.history = {};
    s.settings.trialWindow = [-0.2 0.8];
    s.settings.cleaning = struct('bad', {{{'T7'}, {'T7'}, {}}}, 'highPass', 0.1, 'lowPass', 30, 'notch', 'off', ...
        'notchFreqs', [], 'referenceMode', 'average', 'referenceChannels', {{}}, 'applied', true, 'filterText', ...
        {{['Band-pass filter 0.1-30 Hz: transitions 0.1 and 7.5 Hz, -6 dB cutoffs 0.05 and 33.75 Hz; zero-phase ' ...
        'FIR filter (Hamming-windowed sinc, 16721 taps, order 16720).']}}, ...
        'suggestRule', '');
    s.settings.trials = struct('eventsText', 'S 1 = Standard, S 2 = Target', 'events', {{}}, 'rename', ...
        {{'S  1', 'Standard'; 'S  2', 'Target'}}, 'window', [-0.2 0.8], 'reject', true, 'peakToPeak', 100, ...
        'absolute', 0, 'cut', true);
    s.results.rejection = struct('participant', {'sub-01', 'sub-02', 'sub-03'}, 'total', {70, 70, 70}, ...
        'kept', {62, 62, 61}, 'conditions', {{'Standard', 'Target'}}, 'before', {[40 30], [40 30], [40 30]}, ...
        'after', {[35 27], [36 26], [34 27]}, 'sentence', '');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    % Recorded as read, then cleaned here: no placeholder for cleaning done elsewhere
    verifyHas(tests, txt, ['EEG was recorded from 3 participants [please add: recording system, electrodes and ' ...
        'montage, sampling and online filters].']);
    tests.verifyFalse(contains(txt, 'cleaned before the analysis'), 'Cleaned elsewhere although cleaned here');
    verifyHas(tests, txt, 'The data comprised 32 channels at 250 Hz, referenced to the channel FCz.');
    verifyHas(tests, txt, ['marked as bad (T7; 2 participants of 3) and left out of the average reference, ' ...
        'the trial rejection and the ERPs.']);
    verifyHas(tests, txt, ['filtered with zero-phase windowed-sinc FIR filters designed following published ' ...
        'recommendations (Widmann et al., 2015): Band-pass filter 0.1-30 Hz']);
    verifyHas(tests, txt, 'order 16720');
    verifyHas(tests, txt, 'They were re-referenced offline to the average of the 31 good channels');
    verifyHas(tests, txt, 'around each event (S 1 = Standard and S 2 = Target)');
    verifyHas(tests, txt, ['Epochs with a peak-to-peak amplitude above 100 microvolts on any good channel were ' ...
        'rejected (Standard 15 of 120 and Target 10 of 90; 8 to 9 per participant).']);
    tests.verifyTrue(any(startsWith(refs, 'Widmann A')));
    tests.verifyFalse(any(contains(refs, 'MNE-Python')));
    % Linked mastoids: bad channels are not part of the reference
    s.settings.cleaning.referenceMode = 'linked mastoids';
    s.settings.reference = 'mean of TP9 and TP10 (linked mastoids)';
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, 'marked as bad (T7; 2 participants of 3) and left out of the trial rejection and the ERPs.');
    verifyHas(tests, txt, 'They were re-referenced offline to the mean of TP9 and TP10 (linked mastoids).');
end

function testEEGLayout(tests)
    % Electrode layout (step 1): where the positions came from, only once the layout is confirmed
    s = eegSession();
    txt = MethodsWriter.fromSession(s);
    tests.verifyFalse(contains(txt, 'Electrode positions'), 'Session without a layout: no sentence');

    % From the files only (EEGLAB demo): the turn to one orientation is said
    s.settings.layout = layoutSettings('scalp', struct('file', 32, 'template', 0, 'positionsFile', 0, ...
        'edited', 0, 'none', 0, 'total', 32), {}, ['EEGLAB (x = nose, y = left ear, z = up), turned to x = ' ...
        'right ear, y = nose, z = up; directions from the centre of a sphere fitted to the positions'], ...
        '32 of 32 channels placed: 32 from the file.');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['The data comprised 32 channels at 250 Hz, referenced to the average of all channels. ' ...
        'Electrode positions were taken from the recording files. The coordinates in the recording files were ' ...
        'interpreted as follows: EEGLAB (x = nose, y = left ear, z = up), turned to x = right ear, y = nose, ' ...
        'z = up; directions from the centre of a sphere fitted to the positions. The data files recorded']);
    tests.verifyFalse(contains(txt, '10-5'), 'Nothing placed by name');
    tests.verifyFalse(any(startsWith(refs, 'Jurcak')), 'Template not used, not cited');
    % Positions stored in this orientation (BrainVision): nothing more to say
    s.settings.layout.frame = ['BrainVision (x = right ear, y = nose, z = up); directions from the centre of ' ...
        'a sphere fitted to the positions'];
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, 'Electrode positions were taken from the recording files. The data files recorded');
    % Not confirmed: no sentence
    s.settings.layout.confirmed = false;
    txt = MethodsWriter.fromSession(s);
    tests.verifyFalse(contains(txt, 'Electrode positions'), 'Layout not confirmed: no sentence');

    % From the files and by name, with the counts; one channel without a position
    s.settings.layout = layoutSettings('scalp', struct('file', 30, 'template', 2, 'positionsFile', 0, ...
        'edited', 0, 'none', 1, 'total', 33), {}, ['BrainVision (x = right ear, y = nose, z = up); directions ' ...
        'from the centre of a sphere fitted to the positions; the other channels: 10-5 positions by name ' ...
        '(idealized spherical head; x = right ear, y = nose, z = up)'], ...
        '32 of 33 channels placed: 30 from the file, 2 by name (10-5 system); no position: VEOG.');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Electrode positions were taken for 30 channels from the recording files and for 2 ' ...
        'from their names on the 10-5 system (Oostenveld & Praamstra, 2001; idealized positions on a sphere, ' ...
        'Jurcak et al., 2007). Channel VEOG had no position.']);
    tests.verifyTrue(any(startsWith(refs, ['Oostenveld R, Praamstra P (2001). The five percent electrode ' ...
        'system for high-resolution EEG and ERP measurements. Clin Neurophysiol 112(4):713' char(8211) '719.'])));
    tests.verifyTrue(any(startsWith(refs, ['Jurcak V, Tsuzuki D, Dan I (2007). 10/20, 10/10, and 10/5 systems ' ...
        'revisited: their validity as relative head-surface-based positioning systems. NeuroImage ' ...
        '34(4):1600' char(8211) '1611.'])));
    tests.verifyFalse(contains(txt, 'scaling their angles'), 'nothing scaled: nothing said');
    % The 10-5 positions put on the head of the file's positions (EEGLayout.templateScale)
    s.settings.layout.frame = [s.settings.layout.frame '; the 10-5 positions on this head: angles from the ' ...
        'vertex x 1.21 (fitted on the channels with both)'];
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, ['The 10-5 positions were put on the head of the measured positions by scaling their ' ...
        'angles from the vertex by 1.21 (least-squares fit on the channels that had both).']);
    tests.verifyFalse(contains(txt, 'on this head'), 'the frame clause is not repeated');

    % By name only (EEGLayout on the channel names): old names T3 / T4, a cleaned name, no-position channels
    eeg = struct('labels', {{'Fp1', 'Fz', 'T3', 'T4', 'EEG Cz-REF', 'VEOG', 'A1'}}, 'chanlocs', struct([]));
    L = EEGLayout.fromEEG(eeg, 'Source', 'template');
    s.settings.layout = layoutOf(L, 'template', '', '');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Electrode positions were assigned from the channel names on the 10-5 system ' ...
        '(Oostenveld & Praamstra, 2001; idealized positions on a sphere, Jurcak et al., 2007). Channels T3 and ' ...
        'T4 were treated as T7 and T8 (old 10-20 names). Channels VEOG and A1 had no position.']);
    tests.verifyFalse(contains(txt, 'EEG Cz-REF'), 'A cleaned name is not an old 10-20 name');
    tests.verifyFalse(contains(txt, 'The coordinates in'), 'No file positions, no frame');
    s.settings.layout.renamed = {'T5', 'P7'};
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, 'Channel T5 was treated as P7 (old 10-20 name).');
    % Many channels without a position: the summary shortens the list
    s.settings.layout.summary = ['2 of 12 channels placed: 2 by name (10-5 system); no position: E1, E2, E3, ' ...
        'E4, E5, E6, 4 more.'];
    s.settings.layout.counts = struct('file', 0, 'template', 2, 'positionsFile', 0, 'edited', 0, 'none', 10, ...
        'total', 12);
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, 'Channels E1, E2, E3, E4, E5, E6 and 4 others had no position.');

    % A positions file (as readElectrodes returns it) with its format; T3 found as T7; one channel by hand
    [tl, tp] = EEGLayout.template();
    names = {'Fp1', 'Fp2', 'Fz', 'Cz', 'Pz', 'Oz', 'T7', 'T8'};
    [~, i] = ismember(names, tl);
    P = struct('labels', {names}, 'xyz', 85 * tp(i, :), 'unit', 'mm', 'kind', 'scalp', 'format', 'ASA .elc', ...
        'frame', 'x = right ear, y = nose, z = up, as stored (assumed: .elc files do not state their axes)', ...
        'notes', {{}}, 'fiducials', struct('label', {}, 'xyz', {}), 'file', 'cap32.elc');
    eeg = struct('labels', {{'Fp1', 'Fp2', 'Fz', 'Cz', 'Pz', 'Oz', 'T3', 'T8', 'VEOG'}}, 'chanlocs', struct([]));
    L = EEGLayout.fromEEG(eeg, 'Positions', P);
    s.settings.layout = layoutOf(L, 'auto', 'C:\Users\lab\caps\cap32.elc', P.format);
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Electrode positions were read from cap32.elc (ASA .elc). The coordinates in ' ...
        'cap32.elc were interpreted as follows: x = right ear, y = nose, z = up, as stored (assumed: .elc files ' ...
        'do not state their axes); directions from']);
    verifyHas(tests, txt, 'Channel T3 was treated as T7 (old 10-20 name). Channel VEOG had no position.');
    tests.verifyFalse(any(startsWith(refs, 'Jurcak')), 'Template not used, not cited');
    L = EEGLayout.fromEEG(eeg, 'Positions', P, 'Edits', struct('label', 'VEOG', 'as', 'Iz'));
    s.settings.layout = layoutOf(L, 'auto', '/home/lab/caps/cap32.elc', P.format);
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Electrode positions were taken for 8 channels from cap32.elc (ASA .elc); 1 channel ' ...
        'was placed by hand on the 10-5 system (Oostenveld & Praamstra, 2001; idealized positions on a sphere, ' ...
        'Jurcak et al., 2007).']);
    tests.verifyFalse(contains(txt, 'had no position'), 'Every channel placed');

    % Rodent skull screws (mm from bregma), from the files; then one moved by hand
    s.settings.layout = layoutSettings('skull', struct('file', 4, 'template', 0, 'positionsFile', 0, ...
        'edited', 0, 'none', 0, 'total', 4), {}, ['EEGLAB (x = front, y = left), turned to mm from bregma ' ...
        '(x = right, y = front)'], '4 of 4 channels placed: 4 from the file.');
    [txt, refs] = MethodsWriter.fromSession(s);
    checkClean(tests, txt, refs);
    verifyHas(tests, txt, ['Electrode positions were taken from the recording files and given in mm from bregma ' ...
        '(anterior-posterior, medial-lateral). The coordinates in the recording files were interpreted as ' ...
        'follows: EEGLAB (x = front, y = left), turned to mm from bregma (x = right, y = front).']);
    tests.verifyFalse(contains(txt, '10-5'), 'No 10-5 system on a skull');
    s.settings.layout.counts.file = 3;
    s.settings.layout.counts.edited = 1;
    s.settings.layout.frame = 'mm from bregma (x = right, y = front)';
    txt = MethodsWriter.fromSession(s);
    verifyHas(tests, txt, ['Electrode positions were taken for 3 channels from the recording files; 1 channel was ' ...
        'placed by hand. All electrode positions were given in mm from bregma (anterior-posterior, medial-lateral).']);

    % Confirmed but without any position: nothing to say
    L = EEGLayout.fromEEG(struct('labels', {{'VEOG', 'ECG'}}, 'chanlocs', struct([])));
    s.settings.layout = layoutOf(L, 'auto', '', '');
    txt = MethodsWriter.fromSession(s);
    tests.verifyFalse(contains(txt, 'Electrode positions'), 'No position at all: no sentence');
    tests.verifyFalse(contains(txt, 'had no position'), 'No position at all: no sentence');
end

%% eegSession - Session like EEGAnalysisApp.sessionState on the EEG demo (P300 at Pz)
function [s, res] = eegSession()
    Y = [1.8 6.9 2.8; 1.8 7.3 4.1; 1.6 8.0 5.1; 1.7 6.6 4.7; 1.2 7.2 3.9; 0.6 8.5 4.4; 1.3 6.2 4.4; 0.3 6.4 3.3];
    names = {'Standard', 'Target', 'Novel'};
    res = GroupStats.compare(num2cell(Y, 1), names, 'rm', 'parametric');
    s = Session.new('EEGAnalysisApp');
    s.appTitle = 'EEG Analysis';
    s.inputs = Session.fileInfo('', 'EEG demo (demoEEG), 8 participants');
    parts = arrayfun(@(p) sprintf('sub-%02d_eeglab', p), 1:8, 'UniformOutput', false);
    s.settings = struct('generator', 'demoEEG', 'participants', {parts}, 'maps', {cell(1, 8)}, ...
        'sources', {repmat({'EEGLAB'}, 1, 8)}, 'continuous', false, 'trialWindow', [], 'fs', 250, ...
        'nChannels', 32, 'reference', 'average of all channels', 'history', ...
        {{'Band-pass filtered 0.1 to 30 Hz (pop_eegfiltnew).', 'Re-referenced to the average of all channels (pop_reref).'}}, ...
        'baselineOn', true, 'baseline', [-0.2 0], 'channels', {{'Pz'}}, 'erpsShown', true, ...
        'measure', struct('Measure', 'mean', 'Polarity', 'positive', 'Window', [0.3 0.4], 'Channels', {{'Pz'}}), ...
        'measured', true, 'statsMethod', 'parametric', 'tested', true);
    s.results = struct('conditions', {names}, 'trials', [320 120 80], 'groupTest', res);
    s.summary = {'8 participant(s): ...', sprintf('Test: %s', res.summary)};
end

%% layoutSettings - Confirmed st.settings.layout as the EEG window saves it (source auto, no file, no edits)
function ly = layoutSettings(kind, counts, renamed, frame, summary)
    if isempty(renamed), renamed = cell(0, 2); end
    ly = struct('source', 'auto', 'positionsFile', '', 'edits', struct('label', {}, 'as', {}, 'ap', {}, 'ml', {}), ...
        'confirmed', true, 'kind', kind, 'counts', counts, 'renamed', {renamed}, 'frame', frame, 'format', '', ...
        'summary', summary);
end

%% layoutOf - st.settings.layout of an EEGLayout result, confirmed
function ly = layoutOf(L, source, positionsFile, format)
    count = @(what) sum(strcmp(L.source, what));
    counts = struct('file', count('file'), 'template', count('template'), 'positionsFile', ...
        count('positions file'), 'edited', count('edited'), 'none', numel(L.check.missing), 'total', numel(L.labels));
    ly = layoutSettings(L.kind, counts, L.check.renamed, L.frame, L.summary);
    ly.source = source;
    ly.positionsFile = positionsFile;
    ly.format = format;
end

%% histologySession - Session like HistologyApp.sessionState on the histology demo
function s = histologySession()
    s = Session.new('HistologyApp');
    s.inputs = Session.fileInfo('', 'Histology demo (demoHistology)');
    o = struct('channel', 1, 'backgroundRadiusUm', 15, 'threshold', 0, 'split', true, 'minAreaUm2', 20, ...
        'maxAreaUm2', 2000, 'maxElongation', 2.5, 'minFractionPct', 50, 'markerThreshold', 0, 'pixelSizeUm', 1);
    regions = struct('name', {'Region A', 'Region B'}, 'xy', {[0 0; 200 0; 200 400; 0 400], [200 0; 400 0; 400 400; 200 400]});
    s.settings = struct('generator', 'demoHistology', 'pixelSizeUm', 1, 'pixelSizeFromFile', true, ...
        'channelNames', {{'Nuclei (DAPI)', 'Marker (GFP)'}}, 'imageNames', {{'Culture, day 1', 'Culture, day 3'}}, ...
        'alignChannels', true, 'alignMethod', 'shift', 'alignChannel', 1, 'alignedMethod', 'shift', ...
        'channelsAligned', true, 'landmarks', {{[], []}}, 'count', o, 'regions', regions);
    s.results = struct('shifts', [0 0; 6.4 -9.2], 'landmarkRms', [NaN NaN], ...
        'counts', {{'Culture, day 1', 'Region A', 30, 0.08, 375}});
    s.summary = {'2 image(s), 400 x 400 px, 2 channel(s) (Nuclei (DAPI), Marker (GFP)); pixel size 1 um (from the file)'};
end

%% checkClean - Version, release, no NaN / Inf / [] / leftovers / empty placeholders
function checkClean(tests, txt, refs)
    tests.verifyClass(txt, 'char');
    tests.verifyTrue(iscellstr(refs), 'refs is a cellstr'); %#ok<ISCLSTR>
    verifyHas(tests, txt, sprintf('Neuronal Data Analyzer Lab v%s (Suarez, ', UITheme.version));
    verifyHas(tests, txt, sprintf('MATLAB R%s', version('-release')));
    txtAll = [txt newline strjoin(refs, newline)];
    tests.verifyEmpty(regexp(txtAll, '\<NaN\>', 'once'), 'NaN in the text');
    tests.verifyEmpty(regexp(txtAll, '\<Inf\>', 'once'), 'Inf in the text');
    tests.verifyFalse(contains(txtAll, '[]'), '[] in the text');
    tests.verifyFalse(contains(txtAll, '{{'), 'Unresolved citation');
    tests.verifyEmpty(regexp(txtAll, '&[A-Za-z]+\d?;', 'once'), 'Unresolved &entity;');
    tests.verifyEmpty(regexp(txtAll, '%[-+0#]*[\d.]*[dgsfeiuxc]', 'once'), 'sprintf specifier left in the text');
    tests.verifyEmpty(regexp(txtAll, '\[please add:\s*\]', 'once'), 'Empty placeholder');
    tests.verifyFalse(contains(txtAll, '[please add: value]'), 'A number was missing');
    tests.verifyFalse(contains(txtAll, '  '), 'Double space');
end

function verifyHas(tests, txt, part)
    tests.verifyTrue(contains(txt, part), sprintf('Expected "%s" in:\n%s', part, txt));
end

function assumeDisplay(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end
