%% RegionsImportTest.m
% =========================================================================
% REGIONS FROM IMAGEJ / FIJI (.roi, RoiSet.zip) AND QUPATH (GEOJSON)
% =========================================================================
% core/io/readRegions.m on files written as those programs save them
% (writeImageJRoi for ImageJ; GeoJSON text as QuPath exports it):
% polygon (integer and sub-pixel corners), rectangle and oval ROIs with
% their names, a RoiSet.zip, a line ROI that is skipped, QuPath
% annotations with names or classifications, a MultiPolygon and a hole.
% Coordinates move by +0.5 to MATLAB pixel centres (edge pixels checked
% with inpolygon). No display needed.
% =========================================================================

function tests = RegionsImportTest
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

function f = tmp(tests, name)
    f = fullfile(tests.TestData.dir, name);
end

function testImageJRoi(tests)
    xy = [10 20; 40 22; 35 60; 12 50];
    writeImageJRoi(tmp(tests, 'layer.roi'), xy, 'Layer 2/3');
    R = readRegions(tmp(tests, 'layer.roi'));
    tests.verifyEqual(numel(R), 1);
    tests.verifyEqual(R.name, 'Layer 2/3');
    tests.verifyEqual(R.xy, xy + 0.5);
    tests.verifyEqual(R.source, 'layer.roi');
    % Sub-pixel corners (float32)
    xyf = [10.25 20.5; 40.75 22; 35.5 60.25; 12 50.125];
    writeImageJRoi(tmp(tests, 'sub.roi'), xyf, 'Sub', 'polygon', true);
    R = readRegions(tmp(tests, 'sub.roi'));
    tests.verifyEqual(R.xy, xyf + 0.5, 'AbsTol', 1e-5);
    % Rectangle and oval
    writeImageJRoi(tmp(tests, 'rect.roi'), [5 6 25 16], 'Box', 'rect');
    R = readRegions(tmp(tests, 'rect.roi'));
    tests.verifyEqual(R.xy, [5 6; 25 6; 25 16; 5 16] + 0.5);
    writeImageJRoi(tmp(tests, 'oval.roi'), [0 0 40 20], 'Oval', 'oval');
    R = readRegions(tmp(tests, 'oval.roi'));
    tests.verifyEqual(size(R.xy), [72 2]);
    tests.verifyEqual([min(R.xy(:, 1)) max(R.xy(:, 1)) min(R.xy(:, 2)) max(R.xy(:, 2))], [0 40 0 20] + 0.5, 'AbsTol', 0.05);
    % Not a ROI file
    fid = fopen(tmp(tests, 'bad.roi'), 'w'); fwrite(fid, zeros(1, 80), 'uint8'); fclose(fid);
    tests.verifyError(@() readRegions(tmp(tests, 'bad.roi')), 'NeuroAnalyzer:io:regions');
end

function testRoiSetZip(tests)
    d = tmp(tests, 'set'); mkdir(d);
    writeImageJRoi(fullfile(d, '0001-0010.roi'), [0 0; 10 0; 10 10], 'A');
    writeImageJRoi(fullfile(d, '0002-0020.roi'), [5 6 25 16], 'B', 'rect');
    % A line ROI (type 3) is not an area
    writeImageJRoi(fullfile(d, '0003-0030.roi'), [0 0; 10 0; 10 10], 'Line');
    fid = fopen(fullfile(d, '0003-0030.roi'), 'r+'); fseek(fid, 6, 'bof'); fwrite(fid, 3, 'uint8'); fclose(fid);
    z = tmp(tests, 'RoiSet.zip');
    zip(z, {'0001-0010.roi', '0002-0020.roi', '0003-0030.roi'}, d);
    [R, notes] = readRegions(z);
    tests.verifyEqual({R.name}, {'A', 'B'});
    tests.verifyTrue(any(contains(notes, 'Line')), strjoin(notes, ' | '));
end

function testQuPathGeoJSON(tests)
    txt = ['{"type":"FeatureCollection","features":[' ...
        '{"type":"Feature","id":"a1","geometry":{"type":"Polygon","coordinates":[[[0,0],[20,0],[20,10],[0,10],[0,0]]]},' ...
        '"properties":{"objectType":"annotation","name":"Cortex"}},' ...
        '{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[[30,30],[60,30],[60,60],[30,60],[30,30]],' ...
        '[[40,40],[50,40],[50,50],[40,40]]]},"properties":{"objectType":"annotation","classification":{"name":"Tumor","color":[200,0,0]}}},' ...
        '{"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":[[[[0,50],[10,50],[10,60],[0,50]]],[[[70,0],[80,0],[80,5],[70,5],[70,0]]]]},' ...
        '"properties":{"name":"Islands"}},' ...
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[5,5]},"properties":{"name":"Dot"}}]}'];
    f = tmp(tests, 'annotations.geojson');
    fid = fopen(f, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
    [R, notes] = readRegions(f);
    tests.verifyEqual({R.name}, {'Cortex', 'Tumor', 'Islands 1', 'Islands 2'});
    tests.verifyEqual(R(1).xy, [0 0; 20 0; 20 10; 0 10] + 0.5, 'closing corner dropped');
    tests.verifyEqual(size(R(2).xy), [4 2], 'outer ring of the polygon with a hole');
    tests.verifyEqual(size(R(3).xy), [3 2], 'a triangle');
    tests.verifyEqual(R(4).xy(1, :), [70 0] + 0.5);
    tests.verifyTrue(any(contains(notes, 'hole')), strjoin(notes, ' | '));
    tests.verifyTrue(any(contains(notes, 'Dot')), strjoin(notes, ' | '));
end

function testCountsPerImportedRegion(tests)
    % Cells at known places, counted per region read from a .roi
    xy = [0 0; 20 0; 20 20; 0 20];
    writeImageJRoi(tmp(tests, 'sq.roi'), xy, 'Square');
    R = readRegions(tmp(tests, 'sq.roi'));
    tests.verifyTrue(inpolygon(10, 10, R.xy(:, 1), R.xy(:, 2)));
    tests.verifyFalse(inpolygon(25, 10, R.xy(:, 1), R.xy(:, 2)));
    tests.verifyTrue(inpolygon(1, 1, R.xy(:, 1), R.xy(:, 2)), 'pixel 1 (ImageJ 0-1) is inside');
    tests.verifyTrue(inpolygon(20, 20, R.xy(:, 1), R.xy(:, 2)), 'pixel 20 (ImageJ 19-20) is inside');
    tests.verifyFalse(inpolygon(21, 10, R.xy(:, 1), R.xy(:, 2)), 'pixel 21 is outside');
end
