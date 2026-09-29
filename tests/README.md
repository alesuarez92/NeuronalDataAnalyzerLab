# Neuronal Data Analyzer Lab Tests

## Running tests

**Option 1 – From project root (easiest)**  
Open the project folder in MATLAB, then in the Command Window:

```matlab
run_tests
```

**Option 2 – From MATLAB with path set**

```matlab
cd('/path/to/NeuronalDataAnalyzerLab')
runtests('tests')
```

**Option 3 – Single test file**

```matlab
runtests('tests/ValidationTest')
runtests('tests/ProcessorTest')
runtests('tests/DataLoaderTest')
runtests('tests/SignalFeaturesTest')
runtests('tests/ImagingTest')
```

## Test files

- **ValidationTest** – `Validation.isValidLDFStruct`, `Validation.cropRange`
- **ProcessorTest** – `Processor.crop` (bounds, lengths, mismatched RawStim/RawLDF)
- **DataLoaderTest** – `DataLoader.load(..., 'FromStruct', d)` (no file dialog)
- **SignalFeaturesTest** – every `SignalFeatures` method checked against a Gaussian response with closed-form latency, FWHM, rise/decay time, onset and AUC; negative-going responses; NaN on empty/flat windows
- **EEGFormatsTest** – `core/io` EEG readers: the `demoEEG` study read from EEGLAB (`.set`, `.set` + `.fdt`), FieldTrip, BrainVision (`.vhdr`: Analyzer segments, Recorder INT_16) and plain `.mat` gives the same numbers, conditions, events, positions and history sentences; hand-built EEGLAB / FieldTrip files and BrainVision headers as Recorder and Analyzer write them (Latin-1 / UTF-8, INT_16 / big-endian float32 / ASCII with decimal comma, resolutions and units, markers, amplifier and software filters); the demo's known N1, P300, alpha and VEP; clear errors (missing `.fdt`, truncated data, wrong sizes, unknown variables); history text is read, never run
- **EEGAnalysisTest** – `core/EEGAnalysis`: exact ERP means, SEMs, baseline, difference waves, grand averages and mean / peak measures on a hand-built EEG (edge peaks flagged); on `demoEEG`, P300 Target > Novel > Standard at Pz, N1 negative at Cz near 100 ms, the participant × condition table, the rodent recording cut into 30 trials around its flashes (VEP over V1); plain errors (unknown channel or condition, bad window, data not cut into trials)
- **EEGAnalysisWalkthroughTest** – drives `EEGAnalysisApp` on the demo (ERPs, difference wave, butterfly, P300 measure, repeated-measures ANOVA and Friedman, N1 peak, edge-peak warning, .csv / .mat export, session reopen with the same numbers) and on the rodent recording (cut into trials, VEP) and a plain `.mat` file; frames in `test-artifacts/screens/walkthrough/EEGAnalysisApp_NN_step.png`
- **TechniquesTest** – `core/Techniques` (the table the launcher, Help and website links are built from): every window class exists and has a demo, every tile and step names an existing Help topic, every window that opens sessions is in the table, website pages and anchors exist and the website's Analyses menu is in the launcher's order, Help's *Try it* windows and website pages; the launcher's tile packing (`Main.pack`: families kept together), columns for a window width and the cover crop (no display)
- **MainTest** – the launcher at 3 window sizes (3, 2 and 1 columns, family headings, the cover hidden when narrow; screenshot `Main_small.png` at 720 × 640) and every button pressed: each step opens its window, each **?** and the header Help open the right topic, the body has only the Analyses area (no Learn area); a saved session reopens in the window that saved it, an unknown one is refused
- **ImagingTest** – `core/imaging`: ROI intensity, ΔF/F, movement on RGB stacks, kymograph propagation speed (all three methods), vessel diameter, toolbox-free smoothing and percentile normalization

## Fixtures

- **fixtures/make_valid_ldf_fixture.m** – Script to generate `valid_ldf_export.mat` with minimal LDF export structure. Run once to create the file if needed for manual load tests.
