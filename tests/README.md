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
```

## Test files

- **ValidationTest** – `Validation.isValidLDFStruct`, `Validation.cropRange`
- **ProcessorTest** – `Processor.crop` (bounds, lengths, mismatched RawStim/RawLDF)
- **DataLoaderTest** – `DataLoader.load(..., 'FromStruct', d)` (no file dialog)

## Fixtures

- **fixtures/make_valid_ldf_fixture.m** – Script to generate `valid_ldf_export.mat` with minimal LDF export structure. Run once to create the file if needed for manual load tests.
