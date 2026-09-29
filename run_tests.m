%% run_tests.m
% Run all Neuronal Data Analyzer Lab unit tests from the project root.
%
% Usage: open this folder in MATLAB and run "run_tests", or from command line:
%   matlab -batch "cd('path/to/NeuronalDataAnalyzerLab'); addpath(pwd); run_tests"
%
function run_tests
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'tests'));

    fprintf('Running Neuronal Data Analyzer Lab tests...\n');
    result = runtests(fullfile(root, 'tests'));

    nPass = sum([result.Passed]);
    nFail = sum([result.Failed]);
    nSkip = sum([result.Incomplete]);
    fprintf('\nDone: %d passed, %d failed, %d skipped.\n', nPass, nFail, nSkip);

    if nFail > 0
        for k = 1:numel(result)
            if result(k).Failed
                fprintf('  FAIL: %s\n', result(k).Name);
            end
        end
        % Non-zero exit under "matlab -batch run_tests" (used by CI)
        error('NeuroAnalyzer:tests:failed', '%d test(s) failed.', nFail);
    end
end
