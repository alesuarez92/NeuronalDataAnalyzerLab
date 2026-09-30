%% ImagingFormatsTest.m
% =========================================================================
% IMAGE STACKS FROM MICROSCOPE SOFTWARE (INSCOPIX, THORIMAGE, PRAIRIE VIEW)
% =========================================================================
% core/io/readImagingFolder.m through readImageStack, on files written by
% writeImagingFormat.m as each program saves them: an Inscopix .isxd movie
% (uint16 and float32; the JSON footer: size, rate, pixel size; refused:
% frames with headers, cell sets), a ThorImageLS folder with two channels
% (Experiment.xml + .raw; opened as the folder, the .xml or the .raw), and
% a Bruker Prairie View T-series with two channels (PVScan .xml + one TIFF
% per frame; frame times, microns per pixel). Values, frame rate or
% times, pixel size and channel choice are checked. No display needed.
% =========================================================================

function tests = ImagingFormatsTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

function s = stackOf(H, W, C, N)
    s = uint16(reshape(1:H*W*C*N, H, W, C, N));
    s(1, :, :, :) = s(1, :, :, :) + 1000;                  % top row brighter: orientation check
end

function testInscopix(tests)
    s = stackOf(6, 5, 1, 7);
    f = fullfile(tests.TestData.dir, 'movie.isxd');
    writeImagingFormat('isxd', f, squeeze(s), 'Fps', 20, 'PixelSizeUm', 2.5);
    S = readImageStack(f);
    tests.verifyEqual(S.info.format, 'isxd');
    tests.verifyEqual(S.stack, squeeze(s));
    tests.verifyEqual(S.fps, 20, 'AbsTol', 1e-9);
    tests.verifyEqual(S.pixelSizeUm, 2.5, 'AbsTol', 1e-9);
    % float32 (processed movies, e.g. dF/F)
    x = single(squeeze(s)) / 7;
    writeImagingFormat('isxd', f, x, 'Fps', 10);
    S = readImageStack(f);
    tests.verifyEqual(class(S.stack), 'single');
    tests.verifyEqual(S.stack, x);
    % Frames with headers (raw nVista) and non-movie files are refused
    txt = fileread(f);
    k = strfind(txt, '"hasFrameHeaderFooter":false');
    tests.verifyNotEmpty(k);
    g = fullfile(tests.TestData.dir, 'raw.isxd');
    swapFooter(f, g, '"hasFrameHeaderFooter":false', '"hasFrameHeaderFooter":true ');
    tests.verifyError(@() readImageStack(g), 'NeuroAnalyzer:io:imaging');
    swapFooter(f, g, '"type":0', '"type":1');
    tests.verifyError(@() readImageStack(g), 'NeuroAnalyzer:io:noStack');
end

function swapFooter(f, g, a, b)
    fid = fopen(f, 'r'); raw = fread(fid, Inf, 'uint8=>char')'; fclose(fid);
    raw = strrep(raw, a, b);                                % same length: the footer size is unchanged
    fid = fopen(g, 'w'); fwrite(fid, raw, 'char'); fclose(fid);
end

function testThorImage(tests)
    s = stackOf(4, 6, 2, 5);
    d = fullfile(tests.TestData.dir, 'thor');
    writeImagingFormat('thorimage', d, s, 'Fps', 30, 'PixelSizeUm', 0.8, 'ChannelNames', {'ChanA', 'ChanB'});
    S = readImageStack(d);
    tests.verifyEqual(S.info.format, 'thorimage');
    tests.verifyEqual(S.stack, squeeze(s(:, :, 1, :)));
    tests.verifyEqual(S.fps, 30);
    tests.verifyEqual(S.pixelSizeUm, 0.8);
    tests.verifyEqual(S.info.nChannels, 2);
    S = readImageStack(fullfile(d, 'Experiment.xml'), struct('Channel', 2));
    tests.verifyEqual(S.stack, squeeze(s(:, :, 2, :)));
    S = readImageStack(fullfile(d, 'Image_0001_0001.raw'));
    tests.verifyEqual(size(S.stack, 3), 5);
end

function testPrairieView(tests)
    s = stackOf(5, 4, 2, 6);
    d = fullfile(tests.TestData.dir, 'TSeries-09302026-001');
    t = [0 0.1 0.21 0.3 0.42 0.5];
    writeImagingFormat('prairie', d, s, 'PixelSizeUm', 1.25, 'Times', t, 'ChannelNames', {'Red', 'Green'});
    S = readImageStack(d, struct('Channel', 2));
    tests.verifyEqual(S.info.format, 'prairie');
    tests.verifyEqual(S.stack, squeeze(s(:, :, 2, :)));
    tests.verifyEqual(S.t, t, 'AbsTol', 1e-9);
    tests.verifyEqual(S.fps, 5 / 0.5, 'AbsTol', 1e-9);
    tests.verifyEqual(S.pixelSizeUm, 1.25);
    S = readImageStack(fullfile(d, 'TSeries-09302026-001.xml'));
    tests.verifyEqual(S.stack, squeeze(s(:, :, 1, :)));
    % Not an imaging folder
    e = fullfile(tests.TestData.dir, 'empty');
    mkdir(e);
    tests.verifyError(@() readImageStack(e), 'NeuroAnalyzer:io:unknownFormat');
end
