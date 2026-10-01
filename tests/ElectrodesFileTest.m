%% ElectrodesFileTest.m
% =========================================================================
% UNIT TESTS FOR THE ELECTRODE POSITION FILES (readElectrodes, writeElectrodes)
% =========================================================================
% Every format written from the same positions must read back to the same
% directions in one orientation (x = right ear, y = nose, z = up), with
% the fiducials kept apart. Because a round trip only proves the reader
% agrees with our own writer, each format also has hand-written files laid
% out as the programs that make them write them (EEGLAB .loc / .ced /
% .xyz, BESA .elp / .sfp, EGI HydroCel .sfp, BrainVision .bvef, ASA .elc,
% EasyCap / BioSemi theta-phi lists, BIDS electrodes.tsv, spreadsheets),
% all holding the same electrodes, which must land in the same place.
% Also: skull layouts (mm from bregma), text encodings and line ends, and
% clear errors (unknown format, no name column, Polhemus .elp, wrong
% number of values on a line).
% =========================================================================

function tests = ElectrodesFileTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerElectrodesTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% ------------------------------------------------------------ Round trips

function testRoundTripEveryFormat(tests)
    % The same positions in every format read back to the same directions
    tmp = folder(tests, 'roundtrip');
    [labels, D] = headPositions();
    X = D .* (84 + (1:numel(labels))' / 2);                % mm, a head that is not a sphere
    F = struct('label', {'Nz', 'LPA', 'RPA'}, 'xyz', {[0 94 -31], [-79 -6 -42], [79 -6 -42]});
    withUnit = {'elc', 'bvef', 'csv', 'tsv'};
    for f = {'elc', 'sfp', 'loc', 'locs', 'ced', 'xyz', 'elp', 'bvef', 'txt', 'csv', 'tsv'}
        p = writeElectrodes(fullfile(tmp, ['cap.' f{1}]), labels, X, 'Unit', 'mm', 'Fiducials', F);
        P = readElectrodes(p);
        msg = ['.' f{1}];
        verifyEqual(tests, P.labels, labels, msg);
        verifyEqual(tests, unitRows(P.xyz), D, 'AbsTol', 1e-5, msg);
        verifyEqual(tests, P.kind, 'scalp', msg);
        verifyEqual(tests, {P.fiducials.label}, {'Nz', 'LPA', 'RPA'}, [msg ': fiducials apart']);
        verifyEqual(tests, unitRows(cat(1, P.fiducials.xyz)), unitRows(cat(1, F.xyz)), 'AbsTol', 1e-5, msg);
        verifyEqual(tests, P.file, p);
        verifyNotEmpty(tests, P.format);
        verifySubstring(tests, P.frame, 'x = right ear, y = nose, z = up');
        if any(strcmp(f{1}, withUnit))
            verifyEqual(tests, P.unit, 'mm', msg);
            verifyEqual(tests, P.xyz, X, 'AbsTol', 1e-4, msg);
        else
            verifyEqual(tests, P.unit, '', [msg ': directions only, or the unit is not stated']);
        end
    end
    % Directions only, and other units
    P = readElectrodes(writeElectrodes(fullfile(tmp, 'dir.elc'), labels, D));
    verifyEqual(tests, P.unit, '');
    verifyEqual(tests, P.xyz, D, 'AbsTol', 1e-5);
    verifyTrue(tests, hasNote(P, 'does not state the unit'), strjoin(P.notes, ' | '));
    P = readElectrodes(writeElectrodes(fullfile(tmp, 'dir.bvef'), labels, D));
    verifyEqual(tests, P.unit, '');
    verifyEqual(tests, P.xyz, D, 'AbsTol', 1e-5);
    P = readElectrodes(writeElectrodes(fullfile(tmp, 'cm.elc'), labels, X / 10, 'Unit', 'cm'));
    verifyEqual(tests, P.unit, 'cm');
    verifyEqual(tests, P.xyz, X / 10, 'AbsTol', 1e-5);
    P = readElectrodes(writeElectrodes(fullfile(tmp, 'm.bvef'), labels, X / 1000, 'Unit', 'm'));
    verifyEqual(tests, P.unit, 'mm', 'BrainVision radii are in mm');
    verifyEqual(tests, P.xyz, X, 'AbsTol', 1e-3);
    % The format named explicitly (any extension)
    copyfile(fullfile(tmp, 'cap.sfp'), fullfile(tmp, 'cap.dat'));
    P = readElectrodes(fullfile(tmp, 'cap.dat'), 'Format', 'sfp');
    verifyEqual(tests, P.labels, labels);
    verifyEqual(tests, P.format, 'BESA / EGI .sfp');
end

%% -------------------------------------- Hand-written files, one electrode set

function testSameElectrodesFromEveryProgram(tests)
    % Fpz, T7, Cz, P4 and F3 as each program writes them: they must all
    % land in the same place (directions x = right ear, y = nose, z = up)
    tmp = folder(tests, 'programs');
    names = {'Fpz', 'T7', 'Cz', 'P4', 'F3'};
    want = [0 1 0; -1 0 0; 0 0 1; 0.454519 -0.541675 0.707107; -0.471624 0.603651 0.642788];
    files = struct('file', {}, 'format', {}, 'lines', {});
    % EEGLAB .loc (writelocs: tabs, names padded with dots to four characters)
    files(end + 1) = struct('file', 'cap.loc', 'format', 'EEGLAB .loc', 'lines', {{ ...
        sprintf('1\t0\t0.5\tFpz.'), sprintf('2\t-90\t0.5\tT7..'), sprintf('3\t0\t0\tCz..'), ...
        sprintf('4\t140\t0.25\tP4..'), sprintf('5\t-38\t0.27778\tF3..')}});
    % EEGLAB .locs (spaces)
    files(end + 1) = struct('file', 'cap.locs', 'format', 'EEGLAB .locs', 'lines', {{ ...
        '  1      0    0.5   Fpz', '  2    -90    0.5   T7', '  3      0      0   Cz', ...
        '  4    140   0.25   P4', '  5    -38   0.27778   F3'}});
    % EEGLAB .xyz (x = nose, y = left ear)
    files(end + 1) = struct('file', 'cap.xyz', 'format', 'EEGLAB .xyz', 'lines', {{ ...
        '    1        85         0         0    Fpz', '    2         0        85         0    T7', ...
        '    3         0         0        85    Cz', '    4  -46.0424  -38.6342   60.1041    P4', ...
        '    5   51.3104    40.088   54.6369    F3'}});
    % EEGLAB .ced (pop_chanedit: tab-separated, header row)
    files(end + 1) = struct('file', 'cap.ced', 'format', 'EEGLAB .ced', 'lines', {{ ...
        sprintf('Number\tlabels\ttheta\tradius\tX\tY\tZ\tsph_theta\tsph_phi\tsph_radius\ttype\turchan\tref'), ...
        sprintf('1\tFpz\t0\t0.5\t85\t0\t0\t0\t0\t85\tEEG\t1\t'), ...
        sprintf('2\tT7\t-90\t0.5\t0\t85\t0\t90\t0\t85\tEEG\t2\t'), ...
        sprintf('3\tCz\t0\t0\t0\t0\t85\t0\t90\t85\tEEG\t3\t'), ...
        sprintf('4\tP4\t140\t0.25\t-46.0424\t-38.6342\t60.1041\t-140\t45\t85\tEEG\t4\t'), ...
        sprintf('5\tF3\t-38\t0.27778\t51.3104\t40.088\t54.6369\t38\t40\t85\tEEG\t5\t')}});
    % BESA .elp (type, label, theta, phi)
    files(end + 1) = struct('file', 'cap.elp', 'format', 'BESA .elp', 'lines', {{ ...
        sprintf('EEG\tFpz\t90\t90'), sprintf('EEG\tT7\t-90\t0'), sprintf('EEG\tCz\t0\t0'), ...
        sprintf('EEG\tP4\t45\t-50'), sprintf('EEG\tF3\t-50\t-52')}});
    % BESA .sfp (label x y z, mm)
    files(end + 1) = struct('file', 'cap.sfp', 'format', 'BESA / EGI .sfp', 'lines', {{ ...
        'Fpz 0.0 85.0 0.0', 'T7 -85.0 0.0 0.0', 'Cz 0.0 0.0 85.0', 'P4 38.6342 -46.0424 60.1041', ...
        'F3 -40.0880 51.3104 54.6369'}});
    % ASA .elc (old style: Positions, then Labels)
    files(end + 1) = struct('file', 'cap.elc', 'format', 'ASA .elc', 'lines', {{ ...
        '# ASA electrode file', sprintf('ReferenceLabel\tavg'), sprintf('UnitPosition\tmm'), ...
        sprintf('NumberPositions=\t5'), 'Positions', '0.0000 85.0000 0.0000', '-85.0000 0.0000 0.0000', ...
        '0.0000 0.0000 85.0000', '38.6342 -46.0424 60.1041', '-40.0880 51.3104 54.6369', 'Labels', ...
        'Fpz', 'T7', 'Cz', 'P4', 'F3'}});
    % EasyCap / BioSemi theta-phi list
    files(end + 1) = struct('file', 'cap.txt', 'format', 'Theta / phi list (.txt)', 'lines', {{ ...
        sprintf('Site\t Theta\tPhi'), sprintf('Fpz\t  90\t 90'), sprintf('T7\t -90\t  0'), ...
        sprintf('Cz\t   0\t  0'), sprintf('P4\t  45\t-50'), sprintf('F3\t -50\t-52')}});
    % BIDS electrodes.tsv (CapTrak, m)
    files(end + 1) = struct('file', 'sub-01_space-CapTrak_electrodes.tsv', 'format', 'BIDS electrodes.tsv', ...
        'lines', {{sprintf('name\tx\ty\tz\ttype'), sprintf('Fpz\t0\t0.085\t0\tcup'), ...
        sprintf('T7\t-0.085\t0\t0\tcup'), sprintf('Cz\t0\t0\t0.085\tcup'), ...
        sprintf('P4\t0.0386342\t-0.0460424\t0.0601041\tcup'), sprintf('F3\t-0.040088\t0.0513104\t0.0546369\tcup')}});
    writeLines(fullfile(tmp, 'sub-01_space-CapTrak_coordsystem.json'), ...
        {'{', '  "EEGCoordinateSystem": "CapTrak",', '  "EEGCoordinateUnits": "m"', '}'}, sprintf('\n'));
    for k = 1:numel(files)
        p = fullfile(tmp, files(k).file);
        writeLines(p, files(k).lines, sprintf('\r\n'));
        P = readElectrodes(p);
        msg = files(k).file;
        verifyEqual(tests, P.labels, names, msg);
        verifyEqual(tests, unitRows(P.xyz), want, 'AbsTol', 1e-4, msg);
        verifyEqual(tests, P.format, files(k).format, msg);
        verifyEqual(tests, P.kind, 'scalp', msg);
    end
    P = readElectrodes(fullfile(tmp, 'cap.loc'));
    verifyTrue(tests, hasNote(P, 'Dots padding'), strjoin(P.notes, ' | '));
    verifyEqual(tests, P.unit, '');
    verifySubstring(tests, P.frame, 'EEGLAB polar');
    P = readElectrodes(fullfile(tmp, 'cap.xyz'));
    verifyEqual(tests, P.xyz(4, :), [38.6342 -46.0424 60.1041], 'AbsTol', 1e-9, 'x = -Y, y = X');
    verifySubstring(tests, P.frame, 'EEGLAB (x = nose, y = left ear');
    P = readElectrodes(fullfile(tmp, 'cap.elc'));
    verifyEqual(tests, P.unit, 'mm');
    verifyEqual(tests, P.xyz(4, :), [38.6342 -46.0424 60.1041], 'AbsTol', 1e-9);
    P = readElectrodes(fullfile(tmp, 'sub-01_space-CapTrak_electrodes.tsv'));
    verifyEqual(tests, P.unit, 'm', 'from the coordsystem.json next to it');
    verifyEqual(tests, P.xyz(2, :), [-0.085 0 0], 'AbsTol', 1e-12);
    verifySubstring(tests, P.frame, 'CapTrak');
end

%% ---------------------------------------------------------------- EEGLAB

function testEEGLABCed(tests)
    % pop_chanedit tables: a channel without a position, one with theta /
    % radius only, a fiducial (type FID), columns in another order, and a
    % channel table saved as .csv by a spreadsheet
    tmp = folder(tests, 'ced');
    t = sprintf('\t');
    L = {strjoin({'Number', 'labels', 'theta', 'radius', 'X', 'Y', 'Z', 'sph_theta', 'sph_phi', 'sph_radius', 'type'}, t), ...
        strjoin({'1', 'Fp1', '-17.9', '0.51', '80.4', '26.1', '-2.7', '17.9', '-1.8', '84.6', 'EEG'}, t), ...
        strjoin({'2', 'T7', '-90', '0.5', '0', '84', '0', '90', '0', '84', 'EEG'}, t), ...
        strjoin({'3', 'Cz', '0', '0', '', '', '', '', '', '', 'EEG'}, t), ...
        strjoin({'4', 'VEOG', '', '', '', '', '', '', '', '', 'EOG'}, t), ...
        strjoin({'5', 'Nz', '0', '0.6', '95', '0', '-30', '0', '-17.5', '99.6', 'FID'}, t)};
    writeLines(fullfile(tmp, 'chans.ced'), L, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'chans.ced'));
    verifyEqual(tests, P.labels, {'Fp1', 'T7', 'Cz'});
    verifyEqual(tests, P.xyz(1, :), [-26.1 80.4 -2.7], 'AbsTol', 1e-12, 'RAS = [-Y, X, Z]');
    verifyEqual(tests, P.xyz(2, :), [-84 0 0], 'AbsTol', 1e-12);
    verifyEqual(tests, unitRows(P.xyz(3, :)), [0 0 1], 'AbsTol', 1e-12, 'theta / radius when X, Y, Z are empty');
    verifyEqual(tests, norm(P.xyz(3, :)), median([norm([80.4 26.1 -2.7]), 84]), 'AbsTol', 1e-9);
    verifyEqual(tests, {P.fiducials.label}, {'Nz'});
    verifyEqual(tests, P.fiducials(1).xyz, [0 95 -30], 'AbsTol', 1e-12);
    notes = strjoin(P.notes, ' | ');
    verifyTrue(tests, hasNote(P, 'No position for VEOG'), notes);
    verifyTrue(tests, hasNote(P, 'only theta and radius'), notes);
    verifyTrue(tests, hasNote(P, 'Units not stated'), notes);
    verifyEqual(tests, P.unit, '');
    verifyEqual(tests, P.format, 'EEGLAB .ced');
    % Other column order, LF line ends
    writeLines(fullfile(tmp, 'order.ced'), {strjoin({'labels', 'Z', 'X', 'Y', 'Number'}, t), ...
        strjoin({'Fp1', '-2.7', '80.4', '26.1', '1'}, t), strjoin({'T8', '0', '0', '-84', '2'}, t)}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'order.ced'));
    verifyEqual(tests, P.xyz, [-26.1 80.4 -2.7; 84 0 0], 'AbsTol', 1e-12);
    % An EEGLAB channel table saved as .csv: EEGLAB axes, not x = right ear
    writeLines(fullfile(tmp, 'chans.csv'), {'Number,labels,theta,radius,X,Y,Z,sph_theta,sph_phi,sph_radius,type', ...
        '1,Fp1,-17.9,0.51,80.4,26.1,-2.7,17.9,-1.8,84.6,EEG'}, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'chans.csv'));
    verifyEqual(tests, P.xyz, [-26.1 80.4 -2.7], 'AbsTol', 1e-12);
    verifyEqual(tests, P.format, 'EEGLAB channel table (.csv)');
end

%% ------------------------------------------------------------------ BESA

function testBESAElpVariants(tests)
    % BESA .elp: with and without the type column, a radius column, other
    % types (POL), a comment; and a Polhemus .elp that must be refused
    tmp = folder(tests, 'elp');
    t = sprintf('\t');
    writeLines(fullfile(tmp, 'besa.elp'), {'# electrodes of the 32-channel cap', ['EEG' t 'Fp1' t '-92' t '-72'], ...
        ['EEG' t 'Fz' t '45' t '90'], 'Oz 92 -90', ['T8' t '90' t '0' t '1'], ['POL' t 'VEOG' t '-115' t '-80'], ...
        ['EEG' t 'F4' t '60' t '51' t '1']}, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'besa.elp'));
    verifyEqual(tests, P.labels, {'Fp1', 'Fz', 'Oz', 'T8', 'VEOG', 'F4'});
    fp1 = P.xyz(1, :);
    verifyEqual(tests, fp1, [sind(-92) * cosd(-72), sind(-92) * sind(-72), cosd(-92)], 'AbsTol', 1e-12);
    verifyLessThan(tests, fp1(1), 0, 'Fp1 on the left');
    verifyGreaterThan(tests, fp1(2), 0, 'Fp1 at the front');
    verifyEqual(tests, P.xyz(2, :), [0 sind(45) cosd(45)], 'AbsTol', 1e-12);
    verifyEqual(tests, P.xyz(3, :), [0 -sind(92) cosd(92)], 'AbsTol', 1e-12, 'Oz at the back');
    verifyEqual(tests, P.xyz(4, :), [1 0 0], 'AbsTol', 1e-12, 'T8 on the right');
    verifyEqual(tests, P.unit, '', 'radius 1: directions');
    verifyEqual(tests, P.format, 'BESA .elp');
    verifySubstring(tests, P.frame, 'BESA');
    % A radius on every line (the unit is not stated)
    writeLines(fullfile(tmp, 'radius.elp'), {['EEG' t 'Cz' t '0' t '0' t '9.1'], ['EEG' t 'T7' t '-90' t '0' t '8.6']}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'radius.elp'));
    verifyEqual(tests, P.xyz, [0 0 9.1; -8.6 0 0], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, '');
    verifyTrue(tests, hasNote(P, 'unit is not stated'), strjoin(P.notes, ' | '));
    % Polhemus digitizer .elp
    writeLines(fullfile(tmp, 'polhemus.elp'), {['3' t '2'], '//Probe file', '//Minor revision number', '1', ...
        '//ProbeName', ['%N' t 'Name'], '//Probe type, number of sensors', ['0' t '2'], ...
        '//Position of fiducials X+, Y+, Y- on the subject', ['%F' t '0.0951' t '0.0000' t '0.0000'], ...
        ['%F' t '-0.0042' t '0.0779' t '0.0000'], ['%F' t '0.0042' t '-0.0779' t '0.0000'], '//Sensor type', ...
        ['%S' t '400'], '//Sensor name and data for sensor # 1', ['%N' t 'Fp1'], ['0.0806' t '0.0262' t '0.0021']}, sprintf('\r\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'polhemus.elp')), 'NeuroAnalyzer:eeg:unsupportedFormat');
    try
        readElectrodes(fullfile(tmp, 'polhemus.elp'));
    catch err
        verifySubstring(tests, err.message, 'export the positions as .sfp or .elc');
    end
end

function testEGIHydroCelSfp(tests)
    % EGI HydroCel .sfp (cm): FidNz, FidT9 and FidT10 first, the Cz
    % reference last; head shape points are left out
    tmp = folder(tests, 'egi');
    t = sprintf('\t');
    writeLines(fullfile(tmp, 'GSN-test.sfp'), {['FidNz' t '0' t '9.12' t '-2.41'], ...
        ['FidT9' t '-6.95' t '0.05' t '-3.3'], ['FidT10' t '6.95' t '0.05' t '-3.3'], ...
        ['E1' t '5.71' t '5.62' t '-2.64'], ['E2' t '5.32' t '6.66' t '0.36'], ['E3' t '3.88' t '7.59' t '3.1'], ...
        ['headshape' t '1.2' t '9.8' t '4.0'], ['Cz' t '0' t '0' t '8.95']}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'GSN-test.sfp'));
    verifyEqual(tests, P.labels, {'E1', 'E2', 'E3', 'Cz'});
    verifyEqual(tests, P.xyz(1, :), [5.71 5.62 -2.64], 'AbsTol', 1e-12, 'x = right ear, y = nose, as stored');
    verifyEqual(tests, {P.fiducials.label}, {'FidNz', 'FidT9', 'FidT10'});
    verifyEqual(tests, P.fiducials(2).xyz, [-6.95 0.05 -3.3], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, '');
    verifyTrue(tests, hasNote(P, 'Units not stated'), strjoin(P.notes, ' | '));
    verifyTrue(tests, hasNote(P, 'head shape'), strjoin(P.notes, ' | '));
    verifyFalse(tests, hasNote(P, 'fiducials'), 'the fiducials agree with x = right ear, y = nose');
    % The same file with x = nose, y = left ear: kept as stored, with a note
    writeLines(fullfile(tmp, 'als.sfp'), {'FidNz 9.12 0 -2.41', 'FidT9 0.05 6.95 -3.3', 'FidT10 0.05 -6.95 -3.3', ...
        'E1 5.62 -5.71 -2.64', 'Cz 0 0 8.95'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'als.sfp'));
    verifyEqual(tests, P.xyz(1, :), [5.62 -5.71 -2.64], 'AbsTol', 1e-12);
    verifyTrue(tests, hasNote(P, 'x = nose and y = left ear'), strjoin(P.notes, ' | '));
end

%% ----------------------------------------------------------- BrainVision

function testBrainVisionBvef(tests)
    % As BrainVision Recorder writes them: UTF-8 with a byte-order mark,
    % CRLF; the ground electrode with radius 0 (a direction only)
    tmp = folder(tests, 'bvef');
    L = {'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
        '<BrainVisionElectrodeFile Version="1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">', ...
        '  <Dataset>', '    <ModificationTime>2026-09-30T10:12:44</ModificationTime>', '  </Dataset>', ...
        '  <CapName>test-32</CapName>', ...
        '  <Electrode>', '    <Name>Fp1</Name>', '    <Theta>-90</Theta>', '    <Phi>-72</Phi>', ...
        '    <Radius>1</Radius>', '    <Number>1</Number>', '  </Electrode>', ...
        '  <Electrode>', '    <Name>T8</Name>', '    <Theta>90</Theta>', '    <Phi>0</Phi>', ...
        '    <Radius>1</Radius>', '    <Number>2</Number>', '  </Electrode>', ...
        '  <Electrode>', '    <Name>A&amp;B</Name>', '    <Theta>23</Theta>', '    <Phi>90</Phi>', ...
        '    <Radius>1</Radius>', '    <Number>3</Number>', '  </Electrode>', ...
        '  <Electrode>', '    <Name>GND</Name>', '    <Theta>-60</Theta>', '    <Phi>-90</Phi>', ...
        '    <Radius>0</Radius>', '    <Number>4</Number>', '  </Electrode>', '</BrainVisionElectrodeFile>'};
    writeBytes(fullfile(tmp, 'rec.bvef'), [uint8([239 187 191]), lineBytes(L, sprintf('\r\n'))]);
    P = readElectrodes(fullfile(tmp, 'rec.bvef'));
    verifyEqual(tests, P.labels, {'Fp1', 'T8', 'A&B', 'GND'});
    verifyEqual(tests, P.xyz(1, :), [-cosd(72), sind(72), 0], 'AbsTol', 1e-12, 'as readBrainVision reads [Coordinates]');
    verifyEqual(tests, P.xyz(2, :), [1 0 0], 'AbsTol', 1e-12);
    verifyEqual(tests, P.xyz(3, :), [0 sind(23) cosd(23)], 'AbsTol', 1e-12);
    verifyEqual(tests, P.xyz(4, :), [0 sind(60) cosd(60)], 'AbsTol', 1e-12, 'radius 0: a direction');
    verifyEqual(tests, P.unit, '');
    verifyEqual(tests, P.format, 'BrainVision .bvef');
    % Measured positions (CapTrak): radius in mm
    L = {'<?xml version="1.0" encoding="utf-8"?>', '<BrainVisionElectrodeFile Version="1">', ...
        '<Electrode><Name>Cz</Name><Theta>0</Theta><Phi>0</Phi><Radius>91.5</Radius></Electrode>', ...
        '<Electrode><Name>T7</Name><Theta>-90</Theta><Phi>0</Phi><Radius>78.25</Radius></Electrode>', ...
        '<Electrode><Name>Nasion</Name><Theta>112</Theta><Phi>90</Phi><Radius>96</Radius></Electrode>', ...
        '</BrainVisionElectrodeFile>'};
    writeLines(fullfile(tmp, 'captrak.bvef'), L, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'captrak.bvef'));
    verifyEqual(tests, P.labels, {'Cz', 'T7'});
    verifyEqual(tests, P.xyz, [0 0 91.5; -78.25 0 0], 'AbsTol', 1e-9);
    verifyEqual(tests, P.unit, 'mm');
    verifyEqual(tests, {P.fiducials.label}, {'Nasion'});
    verifyEqual(tests, P.fiducials.xyz, 96 * [0 sind(112) cosd(112)], 'AbsTol', 1e-9);
end

%% ------------------------------------------------------------------- ASA

function testASAElcStyles(tests)
    % Old style (ASA, FieldTrip templates: fiducials among the positions),
    % new style (ANT xensor: 'label : x y z', labels on one line, cm,
    % a polygon section after the labels), and a label count that does
    % not match
    tmp = folder(tests, 'elc');
    t = sprintf('\t');
    writeLines(fullfile(tmp, 'old.elc'), {'# ASA electrode file', ['ReferenceLabel' t 'avg'], ['UnitPosition' t 'mm'], ...
        ['NumberPositions=' t '5'], 'Positions', '-84.3 -18.9 -46.2', '84.1 -19.2 -46.5', '0.4 86.2 -38.9', ...
        '-28.8 84.1 -6.2', '0.3 -0.9 101.7', 'Labels', 'LPA', 'RPA', 'Nz', 'Fp1', 'Cz'}, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'old.elc'));
    verifyEqual(tests, P.labels, {'Fp1', 'Cz'});
    verifyEqual(tests, P.xyz, [-28.8 84.1 -6.2; 0.3 -0.9 101.7], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, 'mm');
    verifyEqual(tests, {P.fiducials.label}, {'LPA', 'RPA', 'Nz'});
    verifyEqual(tests, P.fiducials(3).xyz, [0.4 86.2 -38.9], 'AbsTol', 1e-12);
    verifyEqual(tests, P.format, 'ASA .elc');
    verifySubstring(tests, P.frame, 'assumed');
    writeLines(fullfile(tmp, 'new.elc'), {'# ASA electrode file', ['ReferenceLabel' t 'avg'], ['UnitPosition' t 'cm'], ...
        ['NumberPositions=' t '3'], 'Positions', ['E01 :' t '0.53' t '-0.37' t '11.97'], ...
        ['E02 :' t '-2.71' t '9.05' t '3.88'], ['E03 :' t '7.62' t '-0.41' t '5.33'], 'Labels', ...
        ['E01' t 'E02' t 'E03'], 'NumberPolygons= 1', 'TypePolygons= 1', 'Polygons', '0 1 2'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'new.elc'));
    verifyEqual(tests, P.labels, {'E01', 'E02', 'E03'});
    verifyEqual(tests, P.xyz(2, :), [-2.71 9.05 3.88], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, 'cm');
    writeLines(fullfile(tmp, 'short.elc'), {['UnitPosition' t 'mm'], 'Positions', '1 2 3', '4 5 6', 'Labels', 'Fp1'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'short.elc')), 'NeuroAnalyzer:eeg:badElectrodeFile');
end

%% ---------------------------------------------------------------- Tables

function testTables(tests)
    % BIDS electrodes.tsv (n/a, coordsystem.json with EEGLAB axes), a
    % spreadsheet export with semicolons and decimal commas, a unit column,
    % EEGLAB polar and BESA angle columns, quoted names
    tmp = folder(tests, 'tables');
    t = sprintf('\t');
    bids = {['name' t 'x' t 'y' t 'z' t 'type' t 'material'], ['Fp1' t '80.4' t '26.1' t '-2.7' t 'cup' t 'Ag/AgCl'], ...
        ['T8' t '0' t '-84' t '0' t 'cup' t 'Ag/AgCl'], ['EXG1' t 'n/a' t 'n/a' t 'n/a' t 'n/a' t 'n/a']};
    writeLines(fullfile(tmp, 'sub-02_electrodes.tsv'), bids, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'sub-02_electrodes.tsv'));
    verifyEqual(tests, P.labels, {'Fp1', 'T8'});
    verifyEqual(tests, P.xyz(1, :), [80.4 26.1 -2.7], 'AbsTol', 1e-12, 'no coordsystem.json: as stored');
    verifyEqual(tests, P.unit, '');
    verifyEqual(tests, P.format, 'BIDS electrodes.tsv');
    verifyTrue(tests, hasNote(P, 'No position for EXG1'), strjoin(P.notes, ' | '));
    writeLines(fullfile(tmp, 'sub-02_coordsystem.json'), {'{', '  "EEGCoordinateSystem": "EEGLAB",', ...
        '  "EEGCoordinateUnits": "mm"', '}'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'sub-02_electrodes.tsv'));
    verifyEqual(tests, P.xyz, [-26.1 80.4 -2.7; 84 0 0], 'AbsTol', 1e-12, 'EEGLAB axes turned');
    verifyEqual(tests, P.unit, 'mm');
    verifySubstring(tests, P.frame, 'BIDS EEGLAB');
    % Spreadsheet (semicolons, decimal commas, units in the header)
    writeLines(fullfile(tmp, 'excel.csv'), {'Electrode;X (cm);Y (cm);Z (cm)', 'Fp1;-2,69;8,01;-0,23', ...
        'Cz;0;0;9,4'}, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'excel.csv'));
    verifyEqual(tests, P.labels, {'Fp1', 'Cz'});
    verifyEqual(tests, P.xyz, [-2.69 8.01 -0.23; 0 0 9.4], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, 'cm');
    verifyEqual(tests, P.format, 'Table (.csv)');
    % A unit column; mixed units are converted to mm
    writeLines(fullfile(tmp, 'units.csv'), {'label,x,y,z,unit', 'Fp1,-26.9,80.1,-2.3,mm', '"A,B",0,0,9.4,cm'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'units.csv'));
    verifyEqual(tests, P.labels, {'Fp1', 'A,B'}, 'a quoted name with a comma');
    verifyEqual(tests, P.xyz, [-26.9 80.1 -2.3; 0 0 94], 'AbsTol', 1e-12);
    verifyEqual(tests, P.unit, 'mm');
    verifyTrue(tests, hasNote(P, 'different units'), strjoin(P.notes, ' | '));
    % EEGLAB polar and BESA angle columns
    writeLines(fullfile(tmp, 'polar.csv'), {'channel,theta,radius', 'T7,-90,0.5', 'Pz,180,0.25'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'polar.csv'));
    verifyEqual(tests, P.xyz, [-1 0 0; 0 -sind(45) cosd(45)], 'AbsTol', 1e-12);
    writeLines(fullfile(tmp, 'angles.tsv'), {['Site' t 'Theta' t 'Phi'], ['Fp1' t '-92' t '-72'], ['Fz' t '45' t '90']}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'angles.tsv'));
    verifyEqual(tests, P.xyz(2, :), [0 sind(45) cosd(45)], 'AbsTol', 1e-12);
    % Brain Products list: 'Name Theta Phi', columns lined up with spaces
    writeLines(fullfile(tmp, 'bp.txt'), {'Name   Theta  Phi', 'Fp1      -90  -72', 'Fz        45   90'}, sprintf('\r\n'));
    P = readElectrodes(fullfile(tmp, 'bp.txt'));
    verifyEqual(tests, P.xyz(1, :), [-cosd(72) sind(72) 0], 'AbsTol', 1e-12);
    verifyEqual(tests, P.format, 'Theta / phi list (.txt)');
end

%% ----------------------------------------------------------------- Skull

function testSkullLayouts(tests)
    % Rodent layouts: ap / ml columns (mm or cm from bregma), a planar
    % EEGLAB .xyz (x = anterior, y = left), and the writer's skull tables
    tmp = folder(tests, 'skull');
    writeLines(fullfile(tmp, 'rat.csv'), {'electrode,ap,ml,dv', 'M1-L,2.5,-2.0,-1.0', 'M1-R,2.5,2.0,-1.0', ...
        'V1-L,-6.0,-4.0,-1.0', 'V1-R,-6.0,4.0,-1.0'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'rat.csv'));
    verifyEqual(tests, P.kind, 'skull');
    verifyEqual(tests, P.labels, {'M1-L', 'M1-R', 'V1-L', 'V1-R'});
    verifyEqual(tests, P.xyz, [-2 2.5 0; 2 2.5 0; -4 -6 0; 4 -6 0], 'AbsTol', 1e-12, 'x = ml, y = ap');
    verifyEqual(tests, P.unit, 'mm');
    verifySubstring(tests, P.frame, 'bregma');
    verifyTrue(tests, hasNote(P, 'millimetres were assumed'), strjoin(P.notes, ' | '));
    t = sprintf('\t');
    writeLines(fullfile(tmp, 'mouse.tsv'), {['name' t 'AP (cm)' t 'ML (cm)'], ['S1' t '-0.1' t '0.3'], ['PFC' t '0.2' t '-0.05']}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'mouse.tsv'));
    verifyEqual(tests, P.xyz, [3 -1 0; -0.5 2 0], 'AbsTol', 1e-12, 'cm converted to mm');
    verifyEqual(tests, P.unit, 'mm');
    % EEGLAB .xyz of a rodent montage (all z = 0): a skull layout, ml = -Y, ap = X
    writeLines(fullfile(tmp, 'rat.xyz'), {'1 2.5 2 0 M1-L', '2 2.5 -2 0 M1-R', '3 -6 4 0 V1-L', '4 -6 -4 0 V1-R'}, sprintf('\n'));
    P = readElectrodes(fullfile(tmp, 'rat.xyz'));
    verifyEqual(tests, P.kind, 'skull');
    verifyEqual(tests, P.xyz, [-2 2.5 0; 2 2.5 0; -4 -6 0; 4 -6 0], 'AbsTol', 1e-12);
    verifyTrue(tests, hasNote(P, 'millimetres from bregma were assumed'), strjoin(P.notes, ' | '));
    verifySubstring(tests, P.frame, 'one plane');
    % Writer: skull tables
    ml_ap = [-2 2.5; 2 2.5; -4 -6];
    for f = {'csv', 'tsv', 'txt'}
        P = readElectrodes(writeElectrodes(fullfile(tmp, ['w.' f{1}]), {'A', 'B', 'C'}, ml_ap, 'Kind', 'skull'));
        verifyEqual(tests, P.kind, 'skull', f{1});
        verifyEqual(tests, P.xyz, [ml_ap zeros(3, 1)], 'AbsTol', 1e-12, f{1});
        verifyEmpty(tests, P.notes, f{1});
    end
    P = readElectrodes(writeElectrodes(fullfile(tmp, 'wcm.csv'), {'A', 'B'}, [0.1 0.2; -0.3 0.4], 'Kind', 'skull', 'Unit', 'cm'));
    verifyEqual(tests, P.xyz, [1 2 0; -3 4 0], 'AbsTol', 1e-12);
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.elc'), {'A'}, [1 2], 'Kind', 'skull'), 'NeuroAnalyzer:eeg:badOption');
end

%% ------------------------------------------------------- Text and errors

function testEncodingsAndLineEnds(tests)
    % Latin-1 and UTF-8 names, UTF-16 (spreadsheet "Unicode text"), old Mac
    % line ends (CR only)
    tmp = folder(tests, 'enc');
    name = uint8([77 97 115 116 111 195 175 100 101]);           % 'Mastoide' with i-diaeresis, as UTF-8
    rows = @(nm) [uint8(sprintf('name\tx\ty\tz\n')), nm, uint8(sprintf('\t-70\t-20\t-45\nCz\t0\t0\t90\n'))];
    writeBytes(fullfile(tmp, 'latin1.tsv'), rows(uint8([77 97 115 116 111 239 100 101])));
    writeBytes(fullfile(tmp, 'utf8.tsv'), [uint8([239 187 191]), rows(name)]);
    for f = {'latin1.tsv', 'utf8.tsv'}
        P = readElectrodes(fullfile(tmp, f{1}));
        verifyEqual(tests, uint8(unicode2native(P.labels{1}, 'UTF-8')), name, f{1});
        verifyEqual(tests, P.xyz(2, :), [0 0 90], f{1});
    end
    txt = sprintf('Site\tTheta\tPhi\r\nFp1\t-92\t-72\r\nCz\t0\t0\r\n');
    b = [uint8([255 254]), reshape([uint8(txt); zeros(1, numel(txt), 'uint8')], 1, [])];
    writeBytes(fullfile(tmp, 'unicode.txt'), b);
    P = readElectrodes(fullfile(tmp, 'unicode.txt'));
    verifyEqual(tests, P.labels, {'Fp1', 'Cz'});
    verifyEqual(tests, P.xyz(2, :), [0 0 1], 'AbsTol', 1e-12);
    writeLines(fullfile(tmp, 'mac.sfp'), {'Fp1 -26.9 80.1 -2.3', 'Cz 0 0 94'}, sprintf('\r'));
    P = readElectrodes(fullfile(tmp, 'mac.sfp'));
    verifyEqual(tests, P.labels, {'Fp1', 'Cz'});
end

function testErrors(tests)
    tmp = folder(tests, 'errors');
    t = sprintf('\t');
    writeLines(fullfile(tmp, 'cap.foo'), {'Fp1 1 2 3'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'cap.foo')), 'NeuroAnalyzer:eeg:unsupportedFormat');
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'cap.foo'), 'Format', 'lay'), 'NeuroAnalyzer:eeg:unsupportedFormat');
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'cap.foo'), 'Unit', 'mm'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'none.sfp')), 'NeuroAnalyzer:io:fileNotFound');
    % No name column; names but no positions
    writeLines(fullfile(tmp, 'noname.csv'), {'x,y,z', '1,2,3'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'noname.csv')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    try
        readElectrodes(fullfile(tmp, 'noname.csv'));
    catch err
        verifySubstring(tests, err.message, 'no column of electrode names');
    end
    writeLines(fullfile(tmp, 'nopos.csv'), {'name,impedance', 'Fp1,5'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'nopos.csv')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    % Wrong number of values on a line
    writeLines(fullfile(tmp, 'short.sfp'), {'Fp1 -26.9 80.1 -2.3', 'Cz 0 94'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'short.sfp')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    writeLines(fullfile(tmp, 'short.loc'), {['1' t '-18' t 'Fp1']}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'short.loc')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    writeLines(fullfile(tmp, 'short.xyz'), {'1 80.4 26.1 -2.7'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'short.xyz')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    writeLines(fullfile(tmp, 'comma.csv'), {'name,x,y,z', 'Fp1,-2,69,8,01,-0,23'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'comma.csv')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    try
        readElectrodes(fullfile(tmp, 'comma.csv'));
    catch err
        verifySubstring(tests, err.message, 'decimal comma');
    end
    writeLines(fullfile(tmp, 'empty.csv'), {''}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'empty.csv')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    writeLines(fullfile(tmp, 'nobody.elc'), {['UnitPosition' t 'mm'], 'Labels', 'Fp1'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'nobody.elc')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    writeLines(fullfile(tmp, 'nobody.bvef'), {'<BrainVisionElectrodeFile/>'}, sprintf('\n'));
    verifyError(tests, @() readElectrodes(fullfile(tmp, 'nobody.bvef')), 'NeuroAnalyzer:eeg:badElectrodeFile');
    % Writer
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.foo'), {'A'}, [0 0 1]), 'NeuroAnalyzer:eeg:unsupportedFormat');
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.sfp'), {'A', 'B'}, [0 0 1]), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.sfp'), {'A'}, [0 0 1], 'Unit', 'inch'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.sfp'), {'A'}, [0 0 1], 'Kind', 'brain'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() writeElectrodes(fullfile(tmp, 'w.sfp'), {'A'}, [0 0 1], 'Fiducials', 3), 'NeuroAnalyzer:eeg:badOption');
end

%% --------------------------------------------------------------- helpers

function p = folder(tests, name)
    p = fullfile(tests.TestData.tmp, name);
    if exist(p, 'dir') ~= 7, mkdir(p); end
end

function [labels, D] = headPositions()
    % Directions all over the head (azimuth from the nose to the right, elevation)
    labels = {'Fp1', 'Fpz', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', 'C4', 'T8', ...
        'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
    az = [-17.3 0 18.6 -53.1 -39.4 0 41.2 55.7 -91.3 -64.8 0 63.5 89.2 -127.4 -141.9 180 139.3 126.1 -163.6 180 161.7];
    el = [3.1 1.2 2.4 -1.3 41.7 53.2 39.6 0.4 1.1 47.3 88.2 46.1 -2.2 2.6 39.4 52.7 41.3 -1.4 1.6 -1.1 3.3];
    D = [cosd(el(:)) .* sind(az(:)), cosd(el(:)) .* cosd(az(:)), sind(el(:))];
end

function U = unitRows(X)
    U = X ./ repmat(sqrt(sum(X .^ 2, 2)), 1, 3);
end

function tf = hasNote(P, text)
    tf = any(~cellfun(@isempty, strfind(P.notes, text)));
end

function b = lineBytes(lines, eol)
    b = uint8(double([strjoin(lines, eol) eol]));
end

function writeLines(p, lines, eol)
    writeBytes(p, lineBytes(lines, eol));
end

function writeBytes(p, b)
    fid = fopen(p, 'w');
    fwrite(fid, b, 'uint8');
    fclose(fid);
end
