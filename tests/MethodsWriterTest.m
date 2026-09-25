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
%   - every text names NeuroAnalyzer v<version> and the MATLAB release,
%     and never contains NaN, Inf, [], unresolved {{citations}}, &entities;
%     or sprintf specifiers (%d, %s, %g ...), or an empty placeholder;
%   - histology (demo-like session): images, pixel size, alignment, the
%     counting settings in um, Otsu (1979) cited only for the automatic
%     threshold, markers and regions;
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
    tests.verifyEqual(numel(refs), 1, 'Only the NeuroAnalyzer reference');
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
    tests.verifyEqual(numel(strfind(txt, 'Analyses were performed with NeuroAnalyzer')), 1);
    tests.verifyGreaterThan(strfind(txt, 'Analyses were performed with NeuroAnalyzer'), idx(end), 'Software last');
    tests.verifyEqual(numel(refs), numel(unique(refs)), 'One reference list without duplicates');
    % Paths work too
    f1 = Session.save(fullfile(tests.TestData.dir, 'e'), e);
    f2 = Session.save(fullfile(tests.TestData.dir, 'p'), p);
    tests.verifyEqual(MethodsWriter.fromSessions({f2, f1}), MethodsWriter.fromSessions({e, p}));
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
    verifyHas(tests, txt, sprintf('NeuroAnalyzer v%s (Suarez, ', UITheme.version));
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
