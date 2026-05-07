# NeuroAnalyzer

Neuronal Data Analyzer toolbox (NMD Lab) for LDF (Laser Doppler Flowmetry) and electrophysiology (LFP, MUA) processing and signal characterization.

## Quick start

1. **Add to path** (one time): In MATLAB, run
   ```matlab
   addpath('path/to/NeuroAnalyzer');
   savepath;   % optional: save for future sessions
   ```
2. **Launch**: From the Command Window, type
   ```matlab
   NeuroAnalyzer
   ```

You can also use **Current Folder** to navigate to the NeuroAnalyzer folder and run `NeuroAnalyzer` from there.

## Structure

- **NeuroAnalyzer.m** – Entry point; run this to open the app.
- **Main.m** – Main launcher (in `core/`); three sections: (1) Filtering & signal processing, (2) Imaging & ROI, (3) Signal characterization.- **apps/** – Application windows (Extract LDF, ROI Analysis, Signal Characterization, Help, etc.).
- **core/** – Core logic (theme, project paths, data loading, validation, processing); **core/imaging/** – B&W 256, ROI intensity and movement.
- **docs/** – Help images and documentation.
- **Utilities/** – Third-party utilities (e.g. TDT SDK).

## Requirements

- MATLAB R2018b or later (R2021a+ recommended for Help hyperlinks).
- For TDT data: place or link the TDT MATLAB SDK under `Utilities/` as used by the toolbox.

## Development

- **Tests:** From the project folder in MATLAB, run `run_tests`, or `runtests('tests')`. See `tests/README.md`.
- **License:** See `LICENSE.txt` (All Rights Reserved, use-only terms).

## Author

© Copyrights by Alejandro Suarez, Ph.D.  
[GitHub](https://github.com/alesuarez92)
