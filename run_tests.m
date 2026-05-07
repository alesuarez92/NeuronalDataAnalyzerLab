%% run_tests.m
% Run all NeuroAnalyzer unit tests from the project root.
%
% Usage: open this folder in MATLAB and run "run_tests", or from command line:
%   matlab -batch "cd('path/to/NeuroAnalyzer'); addpath(pwd); run_tests"
%
function run_tests
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'tests'));

    fprintf('Running NeuroAnalyzer tests...\n');
    result = runtests(fullfile(root, 'tests'));

    nPass = sum([result.Passed]);
    nFail = sum([result.Failed]);
    fprintf('\nDone: %d passed, %d failed.\n', nPass, nFail);

    if nFail > 0
        for k = 1:numel(result)
            if result(k).Failed
                fprintf('  FAIL: %s\n', result(k).Name);
            end
        end
    end
end
