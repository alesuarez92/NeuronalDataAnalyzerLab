%% make_valid_ldf_fixture.m
% =========================================================================
% CREATE A MINIMAL VALID LDF EXPORT .MAT FOR MANUAL TESTING
% =========================================================================
% Builds a .mat file in tests/fixtures/ with the structure expected by
% DataLoader: data (concatenated channel vector), datastart, dataend,
% samplerate, and optional metadata (titles, unittext, etc.). Channels 1-6,
% 7, 8 are created (N samples each); typically 6 = stim, 8 = LDF. Run from
% project root or from tests/fixtures/ with project root on path. Output:
% tests/fixtures/valid_ldf_export.mat
% =========================================================================

function make_valid_ldf_fixture()
    % --- Signal length per channel and concatenated data ---
    N = 1000;
    data = [randn(1, N*6), randn(1, N)*0.5, randn(1, N)];  % ch 1-6, 7, 8 (stim, LDF)
    datastart = 1 + (0:7) * N;
    dataend = (1:8) * N;
    samplerate = repmat(1000, 1, 8);

    % --- Optional metadata (same shape as typical LDF export) ---
    titles = arrayfun(@(x) sprintf('Ch%d', x), 1:8, 'UniformOutput', false);
    unittext = repmat({'V'}, 1, 8);
    rangemin = zeros(1, 8);
    rangemax = ones(1, 8);
    blocktimes = [];
    com = [];
    comtext = '';
    firstsampleoffset = zeros(1, 8);

    % --- Save to tests/fixtures/valid_ldf_export.mat ---
    outDir = fileparts(mfilename('fullpath'));
    outFile = fullfile(outDir, 'valid_ldf_export.mat');
    save(outFile, 'data', 'datastart', 'dataend', 'samplerate', ...
         'titles', 'unittext', 'rangemin', 'rangemax', ...
         'blocktimes', 'com', 'comtext', 'firstsampleoffset');
    fprintf('Saved %s\n', outFile);
end
