%% EEGLayoutTest.m
% =========================================================================
% UNIT TESTS FOR ELECTRODE LAYOUTS (core/EEGLayout.m)
% =========================================================================
% The 10-5 template (345 positions, unique names, known directions such
% as Cz up and Fpz in front at 18 deg elevation, left-right symmetry), the
% channel-name cleaning (case, old names T3-T6, 'EEG ' prefixes and
% reference suffixes, bipolar names), and the rule that the same
% electrode from different files lands in the same place: the scalp demo
% of core/demo/demoEEG read from EEGLAB, FieldTrip and BrainVision gives
% the same directions, and the rodent demo from EEGLAB, FieldTrip and
% EEG-BIDS the same mm from bregma. Also: orientation guessing
% on files whose axes were swapped, the duplicate / outside / missing
% reports, the 'Source', 'Positions' and 'Edits' options, the drawing
% coordinates and the plot (only where figures can be drawn).
% =========================================================================

function tests = EEGLayoutTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerEEGLayoutTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoEEG(fullfile(tests.TestData.tmp, 'demo'), 'Participants', 1, ...
        'Kinds', {'scalp', 'rodent'}, 'Formats', {'eeglab', 'fieldtrip', 'brainvision', 'bids'});
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% ----------------------------------------------------------------- Template

function testTemplateCountAndNames(tests)
    [labels, pos] = EEGLayout.template();
    verifyEqual(tests, numel(labels), 345);
    verifyEqual(tests, size(pos), [345 3]);
    verifyEqual(tests, numel(unique(lower(labels))), 345, 'names unique ignoring case');
    verifyEqual(tests, sqrt(sum(pos .^ 2, 2)), ones(345, 1), 'AbsTol', 1e-12, 'unit vectors');
    bad = cellfun(@isempty, regexp(labels, '^[A-Z][A-Za-z]*(z|\d+h?)$', 'once'));
    verifyEmpty(tests, labels(bad), 'every name is <row><z | n | nh>');
    for name = {'Nz', 'NFpz', 'Fp1', 'AFp3h', 'FCC6', 'POO10h', 'OI2h', 'Iz', 'FT7', 'T9h', 'TP10', ...
            'FTT8h', 'TTP7', 'TPP9h', 'FFT10', 'F7', 'AF9h', 'PO8', 'CPP5h', 'T7', 'P8'}
        verifyTrue(tests, any(strcmp(labels, name{1})), sprintf('%s is in the template', name{1}));
    end
    for name = {'FC7', 'C9', 'CP10h', 'FFC8', 'Fp3', 'O3', 'T3', 'A1', 'M1', 'NAS'}
        verifyFalse(tests, any(strcmpi(labels, name{1})), sprintf('%s is not in the template', name{1}));
    end
    [labels2, pos2] = EEGLayout.template();
    verifyEqual(tests, labels2, labels);
    verifyEqual(tests, pos2, pos);
end

function testTemplateKnownDirections(tests)
    at = @(n) templatePos(n);
    verifyEqual(tests, at('Cz'), [0 0 1], 'AbsTol', 1e-12, 'Cz at the vertex');
    verifyEqual(tests, at('Fpz'), [0 cosd(18) sind(18)], 'AbsTol', 1e-12, 'Fpz in front, 18 deg up');
    verifyEqual(tests, at('Oz'), [0 -cosd(18) sind(18)], 'AbsTol', 1e-12, 'Oz at the back');
    verifyEqual(tests, at('T7'), [-cosd(18) 0 sind(18)], 'AbsTol', 1e-12, 'T7 on the left');
    verifyEqual(tests, at('T8'), [cosd(18) 0 sind(18)], 'AbsTol', 1e-12, 'T8 on the right');
    verifyEqual(tests, at('Nz'), [0 1 0], 'AbsTol', 1e-12);
    verifyEqual(tests, at('Iz'), [0 -1 0], 'AbsTol', 1e-12);
    verifyEqual(tests, at('T9'), [-1 0 0], 'AbsTol', 1e-12, 'equator through Nz, T9, Iz, T10');
    verifyEqual(tests, at('T10'), [1 0 0], 'AbsTol', 1e-12);
    verifyEqual(tests, at('Fz'), [0 cosd(54) sind(54)], 'AbsTol', 1e-12);
    verifyEqual(tests, at('C3'), [-cosd(54) 0 sind(54)], 'AbsTol', 1e-12, 'C3 half-way from T7 to Cz');
    fp1 = at('Fp1');
    verifyEqual(tests, fp1, [cosd(18) * sind(-18), cosd(18) * cosd(18), sind(18)], 'AbsTol', 1e-12, ...
        'Fp1 left-front, 18 deg from the midline on the 10 % contour');
    verifyLessThan(tests, fp1(1), 0);
    verifyGreaterThan(tests, fp1(2), 0.9);
    % F3: on the circle through F7, Fz and F8, half-way from F7 to Fz
    fz = at('Fz'); f3 = at('F3'); f7 = at('F7'); f8 = at('F8');
    verifyEqual(tests, f7, [cosd(18) * sind(-54), cosd(18) * cosd(54), sind(18)], 'AbsTol', 1e-12);
    verifyEqual(tests, norm(f3 - fz), norm(f3 - f7), 'AbsTol', 1e-12, 'F3 as far from Fz as from F7');
    verifyEqual(tests, det([f7 - fz; f8 - fz; f3 - fz]), 0, 'AbsTol', 1e-12, 'F3 in the plane of F7, Fz, F8');
    verifyGreaterThan(tests, f3(1), f7(1));
    verifyLessThan(tests, f3(1), fz(1));
    verifyGreaterThan(tests, f3(3), f7(3));
    verifyLessThan(tests, f3(3), fz(3));
end

function testTemplateSymmetry(tests)
    [labels, pos] = EEGLayout.template();
    n = 0;
    for k = 1:numel(labels)
        t = regexp(labels{k}, '^([A-Za-z]+?)(\d+)(h?)$', 'tokens', 'once');
        if isempty(t)
            verifyEqual(tests, pos(k, 1), 0, 'AbsTol', 1e-12, sprintf('%s on the midline', labels{k}));
            continue;
        end
        num = str2double(t{2});
        if mod(num, 2) == 0, continue; end
        j = find(strcmp(labels, sprintf('%s%d%s', t{1}, num + 1, t{3})), 1);
        verifyNotEmpty(tests, j, sprintf('%s has a mirror image', labels{k}));
        if isempty(j), continue; end
        verifyEqual(tests, pos(j, :), [-pos(k, 1), pos(k, 2:3)], 'AbsTol', 1e-12, ...
            sprintf('%s mirrors %s', labels{j}, labels{k}));
        verifyLessThan(tests, pos(k, 1), 0, sprintf('%s on the left', labels{k}));
        n = n + 1;
    end
    verifyEqual(tests, n, 162, 'left-right pairs: 15 full rows x 10 + 6 short rows x 2');
end

%% ------------------------------------------------------------ Name cleaning

function testCleanNames(tests)
    cases = { ...
        'Fp1', 'Fp1', 'exact';  'Cz', 'Cz', 'exact';  '  Oz ', 'Oz', 'exact'; ...
        'FP1', 'Fp1', 'case';  'fpz', 'Fpz', 'case';  'CZ', 'Cz', 'case';  'afp3H', 'AFp3h', 'case'; ...
        'T3', 'T7', 'alias';  't4', 'T8', 'alias';  'T5', 'P7', 'alias';  'T6', 'P8', 'alias'; ...
        'EEG Fp1-REF', 'Fp1', 'cleaned';  'EEG_Cz', 'Cz', 'cleaned';  'EEG-O2', 'O2', 'cleaned'; ...
        'eeg FP2', 'Fp2', 'cleaned';  'C3-LE', 'C3', 'cleaned';  'Pz-avg', 'Pz', 'cleaned'; ...
        'Cz-AR', 'Cz', 'cleaned';  'Fz-Ref', 'Fz', 'cleaned';  'O1-A1', 'O1', 'cleaned'; ...
        'O2-A2', 'O2', 'cleaned';  'C4-M1', 'C4', 'cleaned';  'C3-m2', 'C3', 'cleaned'; ...
        'EEG T3-REF', 'T7', 'cleaned'; ...
        'Fp1-F7', '', '';  'EEG Fp1-F7', '', '';  'A1', '', '';  'A2', '', '';  'M1', '', ''; ...
        'M2', '', '';  'VEOG', '', '';  'HEOG', '', '';  'ECG', '', '';  'EMG1', '', ''; ...
        'NAS', '', '';  'LPA', '', '';  'M1-L', '', '';  'E17', '', '';  '', '', ''; 'EEG', '', ''};
    for k = 1:size(cases, 1)
        [name, how] = EEGLayout.cleanName(cases{k, 1});
        verifyEqual(tests, name, cases{k, 2}, sprintf('name of ''%s''', cases{k, 1}));
        verifyEqual(tests, how, cases{k, 3}, sprintf('how ''%s'' was found', cases{k, 1}));
    end
    [names, hows] = EEGLayout.cleanName({'FP1', 'T3', 'VEOG'});
    verifyEqual(tests, names, {'Fp1', 'T7', ''});
    verifyEqual(tests, hows, {'case', 'alias', ''});
end

%% ------------------------------------------- Same electrode, same place

function testDemoScalpSameDirections(tests)
    d = tests.TestData.demo;
    tr = d.truth.scalp;
    want = tr.posRAS ./ sqrt(sum(tr.posRAS .^ 2, 2));
    files = {d.scalp(1).eeglab, d.scalp(1).fieldtrip, d.scalp(1).brainvision};
    frames = {'EEGLAB (x = nose, y = left ear, z = up), turned to x = right ear, y = nose, z = up', ...
        'FieldTrip ras (x = right ear, y = nose, z = up)', 'BrainVision (x = right ear, y = nose, z = up)'};
    first = [];
    for k = 1:numel(files)
        eeg = EEGSource.open(files{k});
        L = EEGLayout.fromEEG(eeg);
        verifyEqual(tests, L.kind, 'scalp');
        verifyEqual(tests, L.labels, tr.labels);
        verifyEqual(tests, L.pos, want, 'AbsTol', 1e-9, sprintf('%s: directions as written', files{k}));
        verifyTrue(tests, all(strcmp(L.source, 'file')));
        verifyTrue(tests, all(strcmp(L.status, 'ok')));
        verifyEmpty(tests, L.notes, 'no orientation problem');
        verifySubstring(tests, L.frame, frames{k});
        verifySubstring(tests, L.frame, 'sphere fitted');
        verifyEqual(tests, L.summary, '32 of 32 channels placed: 32 from the file.');
        verifyFalse(tests, L.confirmed);
        [pos, kind] = EEGLayout.fromFile(eeg);
        verifyEqual(tests, pos, L.pos, 'AbsTol', 1e-12);
        verifyEqual(tests, kind, 'scalp');
        if isempty(first)
            first = L.pos;
        else
            verifyEqual(tests, L.pos, first, 'AbsTol', 1e-9, 'the same directions from every format');
        end
    end
end

function testDemoRodentSameSkullPositions(tests)
    d = tests.TestData.demo;
    tr = d.truth.rodent;
    want = [tr.ml(:), tr.ap(:), zeros(4, 1)];
    files = {d.rodent.eeglab, d.rodent.fieldtrip, d.rodent.bids};
    for k = 1:numel(files)
        eeg = EEGSource.open(files{k});
        L = EEGLayout.fromEEG(eeg);
        verifyEqual(tests, L.kind, 'skull', files{k});
        verifyEqual(tests, L.pos, want, 'AbsTol', 1e-6, sprintf('%s: mm from bregma', files{k}));
        verifyTrue(tests, all(strcmp(L.source, 'file')));
        verifyTrue(tests, all(strcmp(L.status, 'ok')));
        verifySubstring(tests, L.frame, 'mm from bregma');
        verifyEqual(tests, L.summary, '4 of 4 channels placed: 4 from the file.');
    end
    L = EEGLayout.fromEEG(EEGSource.open(d.rodent.bids));
    verifySubstring(tests, L.frame, 'axes not stated');
    verifyTrue(tests, any(contains(L.notes, 'Orientation not stated')));
    L = EEGLayout.fromEEG(EEGSource.open(d.rodent.eeglab));
    verifyEqual(tests, L.labels, tr.labels);
    verifySubstring(tests, L.frame, 'EEGLAB (x = front, y = left), turned to mm from bregma');
end

%% ------------------------------------------------------- Orientation check

function testOrientationGuess(tests)
    d = tests.TestData.demo;
    eeg = readEEGLAB(d.scalp(1).eeglab);
    good = EEGLayout.fromEEG(eeg);

    % EEGLAB axes (x = nose) labelled as x = right ear: rotated by 90 deg
    e = eeg;
    e.coordSystem = 'BrainVision (x = right ear, y = nose, z = up)';
    L = EEGLayout.fromEEG(e);
    verifyEqual(tests, L.pos, good.pos, 'AbsTol', 1e-9, 'read as x = nose, y = left ear instead');
    verifyNumElements(tests, L.notes, 1);
    verifySubstring(tests, L.notes{1}, 'rotated by 90 deg');
    verifySubstring(tests, L.notes{1}, 'x = nose, y = left ear');
    verifySubstring(tests, L.frame, 'guessed from the channel names');

    % x = right ear positions labelled as EEGLAB: rotated the other way
    ft = readFieldTrip(d.scalp(1).fieldtrip);
    ft.coordSystem = 'EEGLAB (x = nose, y = left ear, z = up)';
    L = EEGLayout.fromEEG(ft);
    verifyEqual(tests, L.pos, good.pos, 'AbsTol', 1e-9);
    verifySubstring(tests, L.notes{1}, 'x = right ear, y = nose');

    % No stated orientation: the better of the two frames
    e.coordSystem = 'Polhemus digitizer';
    L = EEGLayout.fromEEG(e);
    verifyEqual(tests, L.pos, good.pos, 'AbsTol', 1e-9);
    verifySubstring(tests, L.notes{1}, 'rotated by 90 deg');
    e.coordSystem = '';
    L = EEGLayout.fromEEG(e);
    verifyEqual(tests, L.pos, good.pos, 'AbsTol', 1e-9);
    ft.coordSystem = 'Polhemus digitizer';
    L = EEGLayout.fromEEG(ft);
    verifyEqual(tests, L.pos, good.pos, 'AbsTol', 1e-9, 'x = right ear kept when it fits');
    verifySubstring(tests, L.frame, 'axes not stated');
    verifyTrue(tests, any(contains(L.notes, 'Orientation not stated')));

    % Upside down: neither frame fits, the problem is reported
    e = eeg;
    for k = 1:numel(e.chanlocs), e.chanlocs(k).z = -e.chanlocs(k).z; end
    L = EEGLayout.fromEEG(e);
    verifyTrue(tests, any(contains(L.notes, 'far from the 10-5 positions')));
    verifyNotEmpty(tests, L.check.outside);
end

%% ----------------------------------------- Missing, renamed, duplicates, outside

function testReportsByName(tests)
    labels = {'Fz', 'FZ', 'Cz', 'EEG C3-REF', 'T3', 'VEOG', 'A1', 'Fp1-F7', 'X1'};
    L = EEGLayout.fromEEG(makeEEG(labels));
    verifyEqual(tests, L.kind, 'scalp');
    verifyEqual(tests, L.status, {'duplicate', 'duplicate', 'ok', 'renamed', 'renamed', 'none', 'none', 'none', 'none'});
    verifyEqual(tests, L.source, {'template', 'template', 'template', 'template', 'template', '', '', '', ''});
    verifyEqual(tests, L.as, {'Fz', 'Fz', 'Cz', 'C3', 'T7', '', '', '', ''});
    verifyEqual(tests, L.pos(4, :), templatePos('C3'), 'AbsTol', 1e-12);
    verifyEqual(tests, L.pos(5, :), templatePos('T7'), 'AbsTol', 1e-12);
    verifyTrue(tests, all(isnan(L.pos(6, :))));
    c = L.check;
    verifyEqual(tests, c.matched, labels(1:5));
    verifyEqual(tests, c.renamed, {'EEG C3-REF', 'C3'; 'T3', 'T7'});
    verifyEqual(tests, c.missing, {'VEOG', 'A1', 'Fp1-F7', 'X1'});
    verifyEqual(tests, c.duplicated, {'Fz', 'FZ'});
    verifyEmpty(tests, c.outside);
    verifyEqual(tests, L.summary, '5 of 9 channels placed: 5 by name (10-5 system); no position: VEOG, A1, Fp1-F7, X1.');
    verifySubstring(tests, L.frame, '10-5 positions by name');
    lines = EEGLayout.describe(L);
    verifyEqual(tests, lines{1}, L.summary);
    txt = strjoin(lines, ' ');
    verifySubstring(tests, txt, 'EEG C3-REF treated as C3 and T3 treated as T7');
    verifySubstring(tests, txt, 'VEOG (eye channel), A1 (ear lobe or mastoid), Fp1-F7 and X1');
    verifySubstring(tests, txt, 'In the same place: Fz and FZ.');
    verifySubstring(tests, txt, 'Not confirmed yet');

    L = EEGLayout.fromEEG(makeEEG({'VEOG', 'ECG', 'Ch 3'}));
    verifyEqual(tests, L.kind, 'none');
    verifyEqual(tests, L.summary, '0 of 3 channels placed; no position: VEOG, ECG, Ch 3.');
    verifyEqual(tests, EEGLayout.project(L), NaN(3, 2));
end

function testOutsideAndClose(tests)
    % Scalp: one electrode below the chin (150 deg from the vertex), two 1 deg apart
    names = {'Fp1', 'Fp2', 'T7', 'T8', 'Cz', 'Oz', 'Pz', 'Chin', 'Cz2'};
    [~, tp] = templateRows(names(1:7));
    dirs = [tp; 0 sind(30) -cosd(30); sind(1) 0 cosd(1)];
    eeg = makeEEG(names, 90 * dirs + [3 -12 40], 'FieldTrip (ras, mm)');
    L = EEGLayout.fromEEG(eeg);
    verifyEqual(tests, L.pos, dirs, 'AbsTol', 1e-9, 'sphere centre found');
    verifyEqual(tests, L.status, {'ok', 'ok', 'ok', 'ok', 'duplicate', 'ok', 'ok', 'outside', 'duplicate'});
    verifyEqual(tests, L.check.outside, {'Chin'});
    verifyEqual(tests, L.check.duplicated, {'Cz', 'Cz2'});
    txt = strjoin(EEGLayout.describe(L), ' ');
    verifySubstring(tests, txt, 'more than 120 deg from the vertex): Chin');
    verifySubstring(tests, txt, 'Cz and Cz2');

    % Skull: one screw 20 mm out, two 0.07 mm apart
    eeg = makeEEG({'A', 'B', 'C', 'D'}, [-1.5 1 0; 1.5 1 0; 1.55 1.05 0; 20 0 0], 'FieldTrip (bregma, mm)');
    L = EEGLayout.fromEEG(eeg);
    verifyEqual(tests, L.kind, 'skull');
    verifyEqual(tests, L.status, {'ok', 'duplicate', 'duplicate', 'outside'});
    verifyEqual(tests, L.check.outside, {'D'});
    verifySubstring(tests, strjoin(EEGLayout.describe(L), ' '), 'More than 15 mm from bregma: D.');
end

%% ------------------------------------------------------------------ Options

function testSourceOption(tests)
    d = tests.TestData.demo;
    eeg = readEEGLAB(d.scalp(1).eeglab);
    L = EEGLayout.fromEEG(eeg, 'Source', 'template');
    [~, tp] = templateRows(eeg.labels);
    verifyEqual(tests, L.pos, tp, 'AbsTol', 1e-12);
    verifyTrue(tests, all(strcmp(L.source, 'template')));
    verifyEqual(tests, L.as, eeg.labels);
    verifyEqual(tests, L.summary, '32 of 32 channels placed: 32 by name (10-5 system).');

    % auto: the file's positions, the channel without one by name, on the
    % file's head (the demo has Fpz, T7, Oz on the equator: Fz at 45 deg
    % from the vertex where the template has 36 deg)
    whole = EEGLayout.fromEEG(eeg);
    e = eeg;
    e.chanlocs(5).x = NaN;
    L = EEGLayout.fromEEG(e);
    verifyEqual(tests, L.source{5}, 'template');
    verifyEqual(tests, acosd(templatePos('Fz') * whole.pos(5, :)'), 9, 'AbsTol', 1e-6, 'the template is 9 deg off');
    verifyLessThan(tests, acosd(L.pos(5, :) * whole.pos(5, :)'), 2, 'Fz by name next to where the file has it');
    verifyEqual(tests, L.pos(5, 1), 0, 'AbsTol', 1e-12, 'still on the midline');
    verifyEqual(tests, L.summary, '32 of 32 channels placed: 31 from the file, 1 by name (10-5 system).');
    verifySubstring(tests, L.frame, 'the other channels: 10-5 positions by name');
    verifySubstring(tests, L.frame, 'the 10-5 positions on this head: angles from the vertex x 1.21');
    % placed by hand on FT7: half-way from F7 to T7 on this head, not next to FC5
    L = EEGLayout.fromEEG(eeg, 'Edits', struct('label', 'T7', 'as', 'FT7'));
    lab = whole.labels;
    mid = whole.pos(strcmp(lab, 'F7'), :) + whole.pos(strcmp(lab, 'T7'), :);
    t7 = strcmp(lab, 'T7');
    verifyLessThan(tests, acosd(L.pos(t7, :) * mid' / norm(mid)), 3, 'FT7 between F7 and T7');
    verifyGreaterThan(tests, acosd(L.pos(t7, :) * whole.pos(strcmp(lab, 'FC5'), :)'), 15, 'not next to FC5');
    verifySubstring(tests, L.frame, 'the 10-5 positions on this head: angles from the vertex x 1.2');
    % positions that are the template's own: nothing scaled, nothing said
    L = EEGLayout.fromEEG(eeg, 'Source', 'template', 'Edits', struct('label', 'T7', 'as', 'FT7'));
    verifyEqual(tests, L.pos(t7, :), templatePos('FT7'), 'AbsTol', 1e-12);
    verifyFalse(tests, contains(L.frame, 'on this head'));
    L = EEGLayout.fromEEG(e, 'Source', 'file');
    verifyEqual(tests, L.status{5}, 'none');
    verifyEqual(tests, L.summary, '31 of 32 channels placed: 31 from the file; no position: Fz.');

    L = EEGLayout.fromEEG(makeEEG({'Cz', 'Pz'}), 'Source', 'file');
    verifyEqual(tests, L.kind, 'none');
    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Source', 'atlas'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Layout', 'x'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Source'), 'NeuroAnalyzer:eeg:badOption');
end

function testPositionsOption(tests)
    names = {'Fp1', 'Fp2', 'F3', 'F4', 'Cz', 'Pz', 'O1', 'O2', 'T7', 'T8'};
    [~, tp] = templateRows(names);
    P = positionsStruct(names, 90 * tp + [2 -15 40], 'mm', 'scalp');
    % the file's own positions (here: wrong ones) are not used
    labels = {'EEG Fp1-REF', 'FP2', 'F3', 'Cz', 'Pz', 'O1', 'O2', 'T7', 'T8', 'Fz', 'VEOG'};
    eeg = makeEEG(labels, repmat([0 0 85], numel(labels), 1) + (1:numel(labels))' * [1 0 0], ...
        'EEGLAB (x = nose, y = left ear, z = up)');
    L = EEGLayout.fromEEG(eeg, 'Positions', P);
    verifyEqual(tests, L.kind, 'scalp');
    verifyEqual(tests, L.source, [repmat({'positions file'}, 1, 9), {'template', ''}]);
    verifyEqual(tests, L.status, [{'renamed'}, repmat({'ok'}, 1, 9), {'none'}]);
    verifyEqual(tests, L.pos(1:9, :), tp([1 2 3 5:10], :), 'AbsTol', 1e-9, 'directions from the fitted centre');
    verifyEqual(tests, L.pos(10, :), templatePos('Fz'), 'AbsTol', 1e-12);
    verifyEqual(tests, L.check.renamed, {'EEG Fp1-REF', 'Fp1'});
    verifyEqual(tests, L.summary, ['10 of 11 channels placed: 1 by name (10-5 system), 9 from the ' ...
        'positions file; no position: VEOG.']);
    verifySubstring(tests, L.frame, 'positions file (hand-made test file): x = right ear, y = nose, z = up');
    verifyTrue(tests, any(contains(L.notes, '1 position(s) of the positions file belong to no channel')));
    verifyTrue(tests, any(contains(L.notes, 'Written by hand.')));
    L = EEGLayout.fromEEG(eeg, 'Positions', P, 'Source', 'file');
    verifyEqual(tests, L.status{10}, 'none');
    L = EEGLayout.fromEEG(eeg, 'Positions', P, 'Source', 'template');
    verifyTrue(tests, all(strcmp(L.source(1:10), 'template')), 'template ignores the positions');

    % Old name in the positions file (T3) for a channel called T7
    P2 = positionsStruct({'Fp1', 'Cz', 'Oz', 'T3', 'T8', 'Pz'}, ...
        templateRowsPos({'Fp1', 'Cz', 'Oz', 'T7', 'T8', 'Pz'}), '', 'scalp');
    L = EEGLayout.fromEEG(makeEEG({'T7', 'Cz'}), 'Positions', P2);
    verifyEqual(tests, L.status, {'renamed', 'ok'});
    verifyEqual(tests, L.check.renamed, {'T7', 'T3'});
    verifyEqual(tests, L.pos(1, :), templatePos('T7'), 'AbsTol', 1e-9);

    % Skull positions in cm
    d = tests.TestData.demo;
    tr = d.truth.rodent;
    eeg = readEEGLAB(d.rodent.eeglab);
    P3 = positionsStruct(tr.labels, [tr.ml(:), tr.ap(:), zeros(4, 1)] / 10, 'cm', 'skull');
    P3.frame = 'ap and ml columns, mm from bregma (x = right, y = front)';
    L = EEGLayout.fromEEG(eeg, 'Positions', P3);
    verifyEqual(tests, L.kind, 'skull');
    verifyEqual(tests, L.frame, ['positions file (hand-made test file): ap and ml columns, mm from bregma ' ...
        '(x = right, y = front), cm turned to mm']);
    verifyEqual(tests, L.pos, [tr.ml(:), tr.ap(:), zeros(4, 1)], 'AbsTol', 1e-12, 'cm turned to mm');
    verifyTrue(tests, all(strcmp(L.source, 'positions file')));

    L = EEGLayout.fromEEG(makeEEG({'X', 'Y'}), 'Positions', P);
    verifyEqual(tests, L.kind, 'none', 'no name matches (and no 10-5 names)');
    verifyTrue(tests, any(contains(L.notes, 'No channel name was found in the positions file')));
    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Positions', struct('labels', {{'A'}})), ...
        'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Positions', struct('labels', {{'A', 'B'}}, 'xyz', [1 2 3])), ...
        'NeuroAnalyzer:eeg:invalid');
end

function testEditsOption(tests)
    eeg = makeEEG({'Cz', 'X1', 'Fz', 'VEOG'});
    E = struct('label', {'X1', 'Fz', 'Nobody'}, 'as', {'oz', '', 'Pz'}, 'ap', {[], [], []}, 'ml', {[], [], []});
    L = EEGLayout.fromEEG(eeg, 'Edits', E);
    verifyEqual(tests, L.source, {'template', 'edited', '', ''});
    verifyEqual(tests, L.as, {'Cz', 'Oz', '', ''});
    verifyEqual(tests, L.status, {'ok', 'ok', 'none', 'none'});
    verifyEqual(tests, L.pos(2, :), templatePos('Oz'), 'AbsTol', 1e-12);
    verifyTrue(tests, all(isnan(L.pos(3, :))), 'an edit without a place removes the position');
    verifyEqual(tests, L.summary, '2 of 4 channels placed: 1 by name (10-5 system), 1 placed by hand; no position: Fz, VEOG.');
    verifyTrue(tests, any(contains(L.notes, 'The placement of Nobody was not used')));

    % Skull: ap / ml in mm from bregma
    d = tests.TestData.demo;
    eeg = readEEGLAB(d.rodent.eeglab);
    L = EEGLayout.fromEEG(eeg, 'Edits', struct('label', 'M1-L', 'as', '', 'ap', 2, 'ml', -1));
    verifyEqual(tests, L.pos(1, :), [-1 2 0]);
    verifyEqual(tests, L.source{1}, 'edited');
    verifyEqual(tests, L.summary, '4 of 4 channels placed: 3 from the file, 1 placed by hand.');
    L = EEGLayout.fromEEG(makeEEG({'S1', 'S2'}), 'Edits', struct('label', {'S1', 'S2'}, 'ap', {1, -2}, 'ml', {0.5, 3}));
    verifyEqual(tests, L.kind, 'skull');
    verifyEqual(tests, L.pos, [0.5 1 0; 3 -2 0]);

    verifyError(tests, @() EEGLayout.fromEEG(eeg, 'Edits', struct('label', 'M1-L', 'as', 'Cz')), ...
        'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGLayout.fromEEG(makeEEG({'Cz'}), 'Edits', struct('label', 'Cz', 'ap', 1, 'ml', 1)), ...
        'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGLayout.fromEEG(makeEEG({'Cz'}), 'Edits', struct('label', 'Cz', 'as', 'Q99')), ...
        'NeuroAnalyzer:eeg:badOption');
end

%% --------------------------------------------------------- Files, drawing

function testFromFile(tests)
    [pos, kind, frame, notes] = EEGLayout.fromFile(makeEEG({'Cz', 'Pz'}));
    verifyEqual(tests, pos, NaN(2, 3));
    verifyEqual(tests, kind, 'none');
    verifyEmpty(tests, frame);
    verifyEmpty(tests, notes);

    % EEGLAB polar positions only (theta, radius)
    eeg = makeEEG({'T7', 'Cz', 'Fpz', 'O2'});
    th = {-90, 0, 0, 162}; rd = {0.5, 0, 0.4, 0.4};
    [eeg.chanlocs.theta] = deal(th{:});
    [eeg.chanlocs.radius] = deal(rd{:});
    eeg.coordSystem = 'EEGLAB (x = nose, y = left ear, z = up)';
    [pos, kind, ~, notes] = EEGLayout.fromFile(eeg);
    verifyEqual(tests, kind, 'scalp');
    verifyEqual(tests, pos(1, :), [-1 0 0], 'AbsTol', 1e-12);
    verifyEqual(tests, pos(2, :), [0 0 1], 'AbsTol', 1e-12);
    verifyEqual(tests, pos(3, :), templatePos('Fpz'), 'AbsTol', 1e-12);
    verifyEqual(tests, pos(4, :), templatePos('O2'), 'AbsTol', 1e-12);
    verifySubstring(tests, notes{1}, 'polar positions');

    % Unit sphere positions of a BrainVision header, 0 0 0 = no position
    eeg = makeEEG({'Fp1', 'Fp2', 'Cz', 'Oz', 'T7', 'T8', 'X'}, ...
        [templateRowsPos({'Fp1', 'Fp2', 'Cz', 'Oz', 'T7', 'T8'}); 0 0 0], ...
        'BrainVision (x = right ear, y = nose, z = up); on a unit sphere');
    [pos, kind, ~, notes] = EEGLayout.fromFile(eeg);
    verifyEqual(tests, kind, 'scalp');
    verifyEqual(tests, pos(1:6, :), templateRowsPos({'Fp1', 'Fp2', 'Cz', 'Oz', 'T7', 'T8'}), 'AbsTol', 1e-9);
    verifyTrue(tests, all(isnan(pos(7, :))));
    verifyTrue(tests, any(contains(notes, 'at 0, 0, 0')));

    % Two positions at one height are still a scalp layout
    [pos, kind] = EEGLayout.fromFile(makeEEG({'T7', 'T8'}, [-85 0 0; 85 0 0], ...
        'BrainVision (x = right ear, y = nose, z = up)'));
    verifyEqual(tests, kind, 'scalp');
    verifyEqual(tests, pos, [-1 0 0; 1 0 0], 'AbsTol', 1e-12);

    % FieldTrip CTF axes (x = nose, y = left ear) in cm
    names = {'Fp1', 'Fp2', 'Cz', 'Oz', 'T7', 'T8', 'Pz'};
    ras = templateRowsPos(names);
    eeg = makeEEG(names, 9 * [ras(:, 2), -ras(:, 1), ras(:, 3)], 'FieldTrip (ctf, cm)');
    [pos, ~, frame, notes] = EEGLayout.fromFile(eeg);
    verifyEqual(tests, pos, ras, 'AbsTol', 1e-9);
    verifySubstring(tests, frame, 'FieldTrip ctf (x = nose, y = left ear, z = up), turned to');
    verifyEmpty(tests, notes);
    % BIDS CTF and CapTrak
    eeg.coordSystem = 'BIDS CTF (cm)';
    verifyEqual(tests, EEGLayout.fromFile(eeg), ras, 'AbsTol', 1e-9);
    eeg = makeEEG(names, 90 * ras, 'BIDS CapTrak (mm)');
    verifyEqual(tests, EEGLayout.fromFile(eeg), ras, 'AbsTol', 1e-9);
end

function testProject(tests)
    L = EEGLayout.fromEEG(makeEEG({'Cz', 'Fpz', 'T7', 'T8', 'Oz', 'Nz', 'T9', 'VEOG'}));
    xy = EEGLayout.project(L);
    verifyEqual(tests, xy(1:7, :), [0 0; 0 0.8; -0.8 0; 0.8 0; 0 -0.8; 0 1; -1 0], 'AbsTol', 1e-12);
    verifyTrue(tests, all(isnan(xy(8, :))));
    xy = EEGLayout.project(EEGLayout.fromEEG(makeEEG({'C3', 'Fp1'})));
    verifyEqual(tests, xy(1, :), [-0.4 0], 'AbsTol', 1e-12, 'C3 at 36 deg from the vertex');
    verifyEqual(tests, norm(xy(2, :)), 0.8, 'AbsTol', 1e-12, 'Fp1 on the 10 % contour');
    verifyEqual(tests, atan2(xy(2, 1), xy(2, 2)) * 180 / pi, -18, 'AbsTol', 1e-9, 'Fp1 18 deg to the left');

    d = tests.TestData.demo;
    tr = d.truth.rodent;
    xy = EEGLayout.project(EEGLayout.fromEEG(readEEGLAB(d.rodent.eeglab)));
    verifyEqual(tests, xy, [tr.ml(:), tr.ap(:)], 'AbsTol', 1e-12);
end

function testPlotAxes(tests)
    assumeGraphics(tests);
    d = tests.TestData.demo;
    L = EEGLayout.fromEEG(makeEEG({'Fz', 'FZ', 'Cz', 'T3', 'VEOG'}));
    f = figure('Visible', 'off');
    c = onCleanup(@() close(f));
    ax = axes('Parent', f);
    h = EEGLayout.plot(ax, L);
    verifyNumElements(tests, h.labels, 4, 'a name for every placed channel');
    verifyEqual(tests, sort(get(h.electrodes, 'Tag')), sort({'EEGLayout:ok'; 'EEGLayout:renamed'; 'EEGLayout:duplicate'}));
    verifyNotEmpty(tests, h.outline);
    verifyEqual(tests, get(ax, 'DataAspectRatio'), [1 1 1]);
    cla(ax);
    h = EEGLayout.plot(ax, EEGLayout.fromEEG(readEEGLAB(d.rodent.eeglab)), 'Labels', false);
    verifyEmpty(tests, h.labels);
    verifyEqual(tests, get(h.electrodes, 'UserData'), 1:4);
    xl = get(ax, 'XLim');
    verifyLessThan(tests, xl(1), -2.5);
    verifyGreaterThan(tests, xl(2), 2.5);
end

function testPlotUIAxes(tests)
    assumeDisplay(tests);
    L = EEGLayout.fromEEG(makeEEG({'Fp1', 'Fp2', 'Cz', 'Oz'}));
    f = uifigure('Visible', 'off');
    c = onCleanup(@() delete(f));
    ax = uiaxes(f);
    h = EEGLayout.plot(ax, L);
    verifyNumElements(tests, h.labels, 4);
    verifyEqual(tests, get(h.electrodes, 'Tag'), 'EEGLayout:ok');
end

%% ------------------------------------------------------------------ Helpers

function eeg = makeEEG(labels, xyz, coordSystem)
    n = numel(labels);
    locs = [];
    if nargin > 1
        locs = struct('label', labels, 'x', num2cell(xyz(:, 1)'), 'y', num2cell(xyz(:, 2)'), ...
            'z', num2cell(xyz(:, 3)'), 'theta', NaN, 'radius', NaN);
    end
    if nargin < 3, coordSystem = ''; end
    eeg = EEGSource.make(zeros(n, 20), 100, 'Labels', labels, 'Chanlocs', locs, ...
        'CoordSystem', coordSystem, 'Unit', 'uV');
end

function p = templatePos(name)
    [labels, pos] = EEGLayout.template();
    p = pos(strcmp(labels, name), :);
end

function [i, pos] = templateRows(names)
    [labels, tp] = EEGLayout.template();
    [~, i] = ismember(names, labels);
    pos = tp(i, :);
end

function pos = templateRowsPos(names)
    [~, pos] = templateRows(names);
end

function P = positionsStruct(labels, xyz, unit, kind)
    P = struct('labels', {labels}, 'xyz', xyz, 'unit', unit, 'kind', kind, ...
        'format', 'hand-made test file', 'frame', 'x = right ear, y = nose, z = up', ...
        'notes', {{'Written by hand.'}}, 'fiducials', struct('label', {}, 'xyz', {}), 'file', '');
end

function assumeGraphics(tests)
    try
        f = figure('Visible', 'off');
        ax = axes('Parent', f);
        plot(ax, 0, 0);
        close(f);
        canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'figures cannot be drawn here');
end

function assumeDisplay(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end
