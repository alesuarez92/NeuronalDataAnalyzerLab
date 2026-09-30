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
- **TiffMetaTest** – `core/io/tiffMeta`, `unitScale`: ImageJ (escaped `\u00B5m`, Greek mu, hyperstack page order, frame interval and units, cut acquisitions), OME-TIFF (DimensionOrder, sizes, units, time increment, plane times, channel names), ScanImage (saved channels, frame rate, field of view, fast-z slices with flyback, frame timestamps), Aperio MPP and plain resolution tags; `Histology.pixelSizeFromTiff`
- **MainTest** – the launcher at 3 window sizes (3, 2 and 1 columns, family headings, the cover hidden when narrow; screenshot `Main_small.png` at 720 × 640) and every button pressed: each step opens its window, each **?** and the header Help open the right topic, the Learn area has only the Course and Virtual lab (a disabled "Coming soon" button); a saved session reopens in the window that saved it, an unknown one is refused
- **LaserSpeckleTest** – `core/LaserSpeckle`: spatial and temporal contrast of synthetic speckle with a known contrast, the exposure model and its inverse, 1/K² and 1/τc, stimulus onsets; on `demoLSCI`, the contrast of cortex, vessel and static tissue, 1/τc (4000 and 40000 /s), the +21% response of the activated area (true flow +22%) and none elsewhere, the response map, the dark level, contrast and perfusion inputs, the checks and errors; PIMSoft .dat files of versions 1-3 (header, variance and intensity images, contrast and perfusion as PIMSoft computes them, errors for other or cut files) and through `readImageStack`
- **LDFFormatsWalkthroughTest** – drives `ExtractLDFApp` on the LDF demo in every recording format (`core/demo/demoLDFFormats`): flow and stimulus guessed from the names, plots titled with the channel names, comments / markers as the stimulus, another flow channel, a table without a time column (refused without the rate, read with it, the rate reused when its session reopens), a LabChart .mat with two blocks, crop and save with the channel names (opens in LDF Process), sessions reopened with the same crop, a session saved before the channel choice existed, the methods text naming the format; frames in `test-artifacts/screens/walkthrough/ExtractLDFApp_formats_<kind>.png`
- **LSCIWalkthroughTest** – drives `LSCIAnalysisApp` on the demo (Run, response map, average response, checks, contrast and flow displays, exposure model, ROI editing, regular onsets, .csv / .mat export, trials opened by LDF Average, session reopen with the same numbers, report) on perfusion images from a TIFF and on a PIMSoft .dat of the demo (opens as contrast images with its frame rate and pixel size); frames in `test-artifacts/screens/walkthrough/LSCIAnalysisApp_NN_step.png`
- **RegionsImportTest** – `core/io/readRegions`, `writeImageJRoi`: ImageJ polygon (integer and sub-pixel), rectangle and oval ROIs with names, RoiSet.zip (a line ROI skipped), QuPath GeoJSON (names, classifications, MultiPolygon, holes, points skipped), pixel-centre convention; `HistologyWalkthroughTest` imports the demo regions from a RoiSet.zip and a GeoJSON and gets the same counts
- **SignalSourceTest** – `core/io/SignalSource`, `readSignalText`, `readBiopacACQ` / `writeBiopacACQ`: LabChart .mat with several blocks, rates, an empty channel and comments; LabChart and AcqKnowledge text exports; PeriSoft / moorVMS-style tables (decimal comma, clock times, units row, no time column); AcqKnowledge .acq (uncompressed, compressed, big-endian; mixed rates with the extra samples; markers); AcqKnowledge and Spike2 .mat exports; flow and stimulus channels guessed from the names; the stimulus put on the flow channel's time base (faster trigger reduced by the maximum, comments as pulses); the LDF demo written as LabChart text, AcqKnowledge .acq, a PeriSoft-style table, a Spike2 export and a table without a time column (`core/demo/demoLDFFormats`) gives the same flow and stimuli; 'Blood pressure' is not taken as the flow channel
- **ImagingFormatsTest** – `core/io/readImagingFolder` through `readImageStack`, on files from `writeImagingFormat`: Inscopix .isxd (uint16, float32, footer; frames with headers and cell sets refused), ThorImageLS (two channels; folder, .xml or .raw), Prairie View T-series (two channels, frame times, microns per pixel), a folder that is none of them; `ImagingWalkthroughTest` also opens them (and a UCLA Miniscope folder, an ImageJ TIFF with a frame interval and `\u00B5m`) in ROI analysis
- **EphysFormatsTest** – `core/io` electrophysiology readers on files from their synthetic writers: SpikeGLX imec (Neuropixels 1.0 / 2.0 gains, sync word) and nidq, Blackrock NSx 2.1 / 2.3 / 3.0 with NEV digital events and several data blocks, Neuralynx .ncs folders with Events.nev TTLs, Axon ABF 2 (gap-free, episodic with sweep starts, float32; ABF 1 refused), Open Ephys legacy .continuous (CH, ADC, TTL events, first timestamp), Intan RHS2000 (digital and analog inputs, stimulation current, DC data saved), Plexon .plx (versions 107 and 102, AI channels, events, spike times, gaps), Multi Channel Systems HDF5 (electrode, auxiliary and digital streams, events, gaps; MATLAB only)
- **ImagingTest** – `core/imaging`: ROI intensity, ΔF/F, movement on RGB stacks, kymograph propagation speed (all three methods), vessel diameter, toolbox-free smoothing and percentile normalization

## Fixtures

- **fixtures/make_valid_ldf_fixture.m** – Script to generate `valid_ldf_export.mat` with minimal LDF export structure. Run once to create the file if needed for manual load tests.
