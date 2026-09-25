# NeuroAnalyzer Tests

## Running tests

**Option 1 – From project root (easiest)**  
Open the project folder in MATLAB, then in the Command Window:

```matlab
run_tests
```

**Option 2 – From MATLAB with path set**

```matlab
cd('/path/to/NeuroAnalyzer')   % or NeuroAnalyzerLab_MATLAB
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
- **ImagingTest** – `core/imaging`: ROI intensity, ΔF/F, movement on RGB stacks, kymograph propagation speed (all three methods), vessel diameter, toolbox-free smoothing and percentile normalization

## Fixtures

- **fixtures/make_valid_ldf_fixture.m** – Script to generate `valid_ldf_export.mat` with minimal LDF export structure. Run once to create the file if needed for manual load tests.
