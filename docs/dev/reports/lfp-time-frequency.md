# Wave 1 report: LFP time–frequency analysis (+ headless ERP analysis)

Classification: part of the wave-1 EXISTING STRAND (area: LFP time–frequency).
Nothing here has been run in real MATLAB yet. The numeric core and the
features tests were run in Octave 8 (see "Verification" below). The UI code
was parse-checked only.

## Files

Changed
- `apps/LFPAnalysisApp.m` (+730 / −49 lines).
  - New step card **6 Time–frequency** and 4 new tabs.
  - ERP onset detection, averaging and CSD now call `core/ERPAnalysis`.
  - New public methods (see API).

New
- `core/TimeFrequency.m`: toolbox-free spectral analysis (static methods).
- `core/ERPAnalysis.m`: the headless onset detection, ERP averaging and CSD that used to live inside the app.
- `core/demo/demoLFPOscillations.m`: generates `DemoData.lfpFile()` plus 6 Hz theta and a phase-locked 40 Hz burst, with the ground truth.
- `tests/LFPFeaturesTest.m`: 15 unit tests.
- `tests/LFPWalkthroughTest.m`: 2 UI tests that save frames `LFPAnalysisApp_x01..x06_*.png`.
- `docs/dev/reports/lfp-time-frequency.md`: this report.

`git diff --stat` for the tracked file: `apps/LFPAnalysisApp.m | 779 +++++++++++++++++++++++++++++++++++++++++++++++-----`

## New public API

### `core/ERPAnalysis.m`

Static methods, base MATLAB only.

```matlab
[onsetTimes, onsetIdx] = ERPAnalysis.detectOnsets(stim, fs, threshold, minISI)
[erpAvg, erpStd, t, nValid, epochs, valid] = ERPAnalysis.average(lfp, fs, onsetTimes, preS, postS)
csd = ERPAnalysis.csd(erp, spacingUm, order)      % order optional (default all rows), >= 3 rows
```

This is exactly the maths the app used before:
- onsets are upward crossings of the mean-subtracted stimulus;
- an onset closer than minISI to the previous crossing is dropped;
- onset time is `(k-1)/fs`;
- the onset sample in the LFP is `round(t*fs)+1`;
- edge epochs are NaN-filled and excluded with `'omitnan'`;
- CSD is `-diff(erp,2,1)/dz^2` with `dz = spacingUm*1e-6`, and the edge rows are replicated.

The app now calls these functions. A test checks that the results are **bit-identical** to a verbatim copy of the old app code.

Two deliberate robustness changes:
1. With no threshold crossing, `detectOnsets` returns empty. The old inline code threw "Index exceeds…" (`onsets([true])` on an empty array) before reaching the app's own "No stimulus onsets detected" message, so that message now actually appears.
2. A column-vector stimulus now works; the old `[0 above]` concatenation failed on it.

Error IDs:
- `NeuroAnalyzer:ERPAnalysis:stimNotVector`
- `NeuroAnalyzer:ERPAnalysis:badSpacing`
- `NeuroAnalyzer:ERPAnalysis:tooFewChannels`

### `core/TimeFrequency.m`

Static methods, base MATLAB `fft`/`ifft` only.

```matlab
[pxx, f]  = TimeFrequency.welchPSD(x, fs, segSec=2, overlap=0.5, nfft)     % Hann, one-sided density
[P, f, t] = TimeFrequency.stft(x, fs, winSec=0.5, overlap=0.9, fRange)     % spectrogram (PSD per window)
[coef, pow, phase] = TimeFrequency.morletTF(x, fs, freqs, nCycles=7)       % unit-energy complex Morlet
[p, z]    = TimeFrequency.bandPower(x, fs, bands)                          % |analytic band signal|^2
r         = TimeFrequency.eventBandPower(x, fs, onsets, window, bands, baselineWindow)
[erspDb, itpc, t, info] = TimeFrequency.ersp(x, fs, onsets, window, freqs, baselineWindow, nCycles=7)
bands     = TimeFrequency.defaultBands()    % struct array name/range: delta 1-4 ... gamma 30-80 Hz
```

Signals are vectors, or matrices with one signal per row. `morletTF` and `bandPower` accept matrices. `stft`, `eventBandPower` and `ersp` take a single signal.

Methods:

- **welchPSD**
  - Uses a periodic Hann window. Each segment's mean is removed.
  - Scaling is one-sided density, so `sum(pxx)*df` equals the variance (Parseval).
- **morletTF**
  - The wavelet is `exp(2πift)·exp(−t²/2s²)` with `s = nCycles/(2πf)`. It is truncated at ±3s and normalised to unit energy.
  - Convolution is done by FFT and keeps the 'same' part. The row mean is removed first.
  - Phase convention: a cosine peak has phase 0.
- **bandPower**
  - FFT band-pass with gain 1 inside `[lo hi]` and raised-cosine edges of width `w = min(2, max(0.1, (hi−lo)/4))` Hz just outside the band.
  - Negative frequencies are dropped, which gives the analytic signal: the FFT form of band-pass plus Hilbert.
  - The signal is mirror-extended to limit edge effects.
  - A sinusoid of amplitude A in the band gives p = A².
- **eventBandPower**
  - Epochs of the continuous band power, expressed as % change from the trial-averaged baseline.
  - Returns `r.mean` and `r.sem` (nBands × time), `r.nTrials` per band, and `r.power` / `r.pctChange` (NaN for trials that were not used).
  - For each band, an epoch is used only if it lies at least `1/w` s (the filter settling time) from the recording ends.
- **ersp**
  - Epochs come from the continuous signal (mean removed): window `[tmin tmax]` around each onset, onset sample `round(onset*fs)+1`.
  - `ERSP = 10·log10(mean_k P_k / B(f))`, where B is the trial-averaged power in the baseline window.
  - `ITPC = |mean_k coef/|coef||`.
  - At each frequency, only the epochs whose wavelet support (window ± 3s) lies inside the recording are used (`info.nTrialsPerFreq`). Nothing is padded or invented.

Error IDs:
- `NeuroAnalyzer:TimeFrequency:badFreqs`, `badCycles`, `badBand`, `badWindow`, `badBaseline`
- `noEpochs`, `notVector`, `tooShort`, `emptyRange`, `empty`

### `apps/LFPAnalysisApp.m`

All new methods are public and dialog-free, and return `true` on success.

```matlab
ok = app.loadOscillationDemo()               % demoLFPOscillations -> tempdir/NeuroAnalyzerDemo/demo_lfp_oscillations.mat
ok = app.runSpectrum(ch)                     % ch optional (default: step-6 channel)
ok = app.runSpectrogram(ch, fRange)          % fRange [fmin fmax] Hz, optional
ok = app.runERSP(ch, fRange, baseline)       % baseline [t1 t2] s, optional
ok = app.runBandPower(ch, bands)             % bands: {'Theta','Gamma'} | n x 2 [lo hi] | struct(name, range) | [] = ticked table rows
```

Arguments that are passed are written into the step-6 fields first, as `computeCSD(spacing, order)` already does. Invalid input sets an error status, shows a `UIKit.alert` and returns `false`.

New properties:
- controls: `TFChannelDrop`, `TFFminEdit`, `TFFmaxEdit`, `TFCyclesEdit`, `TFEpochFromEdit`, `TFEpochToEdit`, `TFBaseFromEdit`, `TFBaseToEdit`, `BandTable`, `OscDemoBtn`, `SpectrumBtn`, `SpectrogramBtn`, `ERSPBtn`, `BandPowerBtn`, `LeftGrid`;
- tabs and axes: `TabSpectrum`, `TabSpectrogram`, `TabERSP`, `TabBandPower`, `AxSpectrum`, `AxSpectrogram`, `AxERSP`, `AxITPC`, `BandContainer`;
- results: `LastSpectrum`, `LastSpectrogram`, `LastERSP`, `LastBandPower`;
- state: `TFDone`, `TFFocus`.

UI details:

- **Step 6 card**, from top to bottom:
  - **Try oscillation demo**;
  - Channel;
  - Frequencies (Hz) [2]–[80];
  - Wavelet cycles [7];
  - Epoch (s) [−0.5]–[1];
  - Baseline (s) [−0.4]–[−0.1];
  - a hint that says the band limits are conventions and can be edited;
  - an editable band table (Band | Low (Hz) | High (Hz) | Plot) with the defaults delta 1–4, theta 4–8, alpha 8–13, beta 13–30 and gamma 30–80 Hz. Invalid edits are reverted with a warning;
  - the buttons **Spectrum**, **Spectrogram**, **ERSP / ITPC** and **Band power**.
- **Tabs:**
  - **Spectrum**: Welch PSD on log–log axes, with the table's bands shaded and labelled.
  - **Spectrogram**: STFT power in dB (parula, robust colour limits), with dashed stimulus-onset lines.
  - **ERSP / ITPC**: side by side.
    - ERSP in dB uses a diverging theme blue → white → vermillion map with symmetric colour limits centred on 0. A dashed t = 0 line and dotted baseline edges are drawn.
    - ITPC is shown on a 0–1 scale.
    - Frequencies without trials are left blank.
  - **Band power**: one tile per band, showing % change versus baseline as mean ± SEM, with t = 0 and 0 % lines.
- **Busy dialog:** every step-6 computation runs inside `UIKit.busy`/`UIKit.done`, including the error path.
- **Stimulus onsets:** ERSP, band power and the spectrogram markers use the same detection as the ERP. The threshold and min ISI come from the last ERP run, or 0.5 and 0.5 s before the first run.
- **Next step:** `updateControls` still moves a single primary button. After **Try oscillation demo**, or once any step-6 action has run, the primary button walks through Spectrum → Spectrogram → ERSP / ITPC → Band power, then falls back to the existing Load → ERP → CSD → Export chain.
- **Layout:** the left column already scrolled.
  - The channel card changed from `'1x'` to a fixed 170 px. In a scrolling grid a `'1x'` row can collapse to nothing.
  - **Try oscillation demo** scrolls the column to the bottom (`scroll`, wrapped in try/catch).
- **Header:** the subtitle now mentions oscillations.
- **Unchanged:** the ERP and CSD behaviour, all earlier public methods, and the no-argument, non-blocking constructor.

## Demo generator

`s = demoLFPOscillations()` returns `DemoData.lfpFile()` with two additions:

- **Theta:** 6 Hz, a constant 40 µV, identical on all 8 channels, so it cancels in the CSD.
  - The instantaneous frequency wanders with SD 0.5 Hz and a correlation time of ~0.5 s, so the phase is not locked to the stimuli.
  - Truth: `s.truth.theta = struct(freqHz 6, amplitudeV 40e-6, channels 1:8, phaseLocked false, freqJitterSdHz 0.5)`.
- **Gamma:** a 40 Hz burst from 50 to 250 ms after each onset on channels 3–5.
  - Amplitude 10 µV with a flat top and 25 ms raised-cosine ramps.
  - It starts at the same phase every time, so it is phase-locked.
  - Truth: `s.truth.gamma = struct(freqHz 40, amplitudeV 10e-6, channels 3:5, phaseLocked true, windowS [0.05 0.25], rampS 0.025)`.
- **Determinism:** the base recording uses DemoData's seed; the theta wander uses `RandStream('mt19937ar','Seed',DemoData.Seed+101)`.

**To wire into DemoData (lead):**
- add a kind `'lfpOscillations'` → `demoLFPOscillations()` → `demo_lfp_oscillations.mat` in `DemoData.file`/`writeAll`;
- `loadOscillationDemo` could then use `DemoData.file('lfpOscillations')`. Today it regenerates the file on every call, which takes about 1 s;
- add `addpath(fullfile(root,'core','demo'))` to `NeuroAnalyzer.m` and `run_tests.m`. The app adds it itself if needed (`ensureDemoPath`), and both test files add it in `setupOnce`.

## Tests

### `tests/LFPFeaturesTest.m` (15 tests)

In Octave the whole file runs in about 0.5 s.

1. `testMorletPeaksAtSinusoidFrequency`: 25 Hz cosine → mean Morlet power peaks at 25 ± 1 Hz. The phase equals 2π·25·t (±0.05 rad). A matrix input gives freq × time × rows and is linear.
2. `testMorletUnitEnergyFlatForWhiteNoise`: white noise → mean power / variance = 1 ± 15 % at 10, 20, 40 and 80 Hz. This confirms the unit-energy normalisation.
3. `testMorletRejectsBadFrequencies`: 0 Hz and ≥ Nyquist raise `badFreqs`.
4. `testWelchPeakAndParseval`: 50 Hz sinusoid plus noise. The peak is at 50 Hz ± df, the total power matches the variance within 2 %, and the noise floor is 2σ²/fs within 10 %.
5. `testStftTracksFrequencyChange`: a signal that switches from 10 to 30 Hz. The peak frequency per window follows it within ±2 Hz, and the window power is 0.5 within 10 %.
6. `testBandPowerCalibration`: A·sin(6 Hz) gives A² in 4–8 Hz within 1 % and less than 1e-3·A² in 30–80 Hz.
7. `testBandPowerThetaConstant` (demo channel 8):
   - the mean theta power over 2 s bins equals A² within 20 %;
   - the bin-to-bin coefficient of variation is below 0.25;
   - the event-related theta change averages less than 25 %.
8. `testEventBandPowerGammaBurst` (demo channel 4):
   - 30–80 Hz power rises by more than 100 % at 100–200 ms;
   - late (0.5–0.9 s) change is under 40 %;
   - at least 13 trials are used;
   - SEM ≥ 0.
9. `testErspGammaBurstAndItpc` (demo channel 4, 4–80 Hz):
   - ERSP at 36–44 Hz, 100–200 ms is above 6 dB;
   - late mean is under 1.5 dB overall and under 3 dB at 36–44 Hz;
   - pre-stimulus mean is under 1 dB at 36–44 Hz;
   - ITPC is above 0.8 in the burst, below 0.5 late at 40 Hz, and below 0.75 for theta late;
   - channel 8 shows less than 3 dB of 40 Hz ERSP.
10. `testErspEdgeTrialsAndErrors`:
    - an onset at 1 s is dropped at 4 Hz, where the wavelet reaches before t = 0, but kept at 40 Hz (`nTrialsPerFreq = [1 2]`);
    - a baseline outside the epoch raises `badBaseline`;
    - an edge-only onset raises `noEpochs`.
11. `testErpAnalysisMatchesPreviousApp` (`DemoData.lfpFile`):
    - `detectOnsets`, `average` and `csd` are **bit-identical** (`verifyEqual` with no tolerance) to a verbatim copy of the old app code, in both channel orders;
    - 15 onsets at the true times (within 1 sample);
    - N1 at 15 ± 3 ms on channel 4, the deepest channel is 4, and the CSD sink is at channel 4.
12. `testDetectOnsetsEdgeCases`:
    - the min-ISI drop and `(k−1)/fs` timing are correct;
    - a column stimulus gives the same result;
    - no crossings gives empty with no error;
    - a matrix stimulus raises an error.
13. `testAverageSkipsEdgeEpochs`: epochs at both edges are excluded (`valid`, `nValid`), and the mean and SD come from the complete epochs only.
14. `testCsdQuadraticProfile`: V = z² gives CSD = −2 everywhere (edge rows replicated). Also checks the tooFewChannels and badSpacing errors.
15. `testOscillationDemoGroundTruth`:
    - the added signal equals the truth: theta amplitude, the same theta on every channel, the gamma amplitude, gamma only on channels 3–5 and only within 50–250 ms;
    - the theta PSD peaks at 6 ± 1 Hz.

### `tests/LFPWalkthroughTest.m` (2 tests)

These are skipped when there is no display. Frames go to `test-artifacts/screens/walkthrough/`.

`testLFPTimeFrequency` saves one frame after each step:

| Frame | Step | Checks |
|---|---|---|
| `LFPAnalysisApp_x01_oscillation_demo_loaded` | `loadOscillationDemo` | channel 4 is selected |
| `_x02_spectrum` | `runSpectrum(4)` | theta peak at 6 ± 1 Hz |
| `_x03_spectrogram` | `runSpectrogram(4, [2 80])` | 15 onsets marked |
| `_x04_ersp_itpc` | `runERSP(4, [4 80], [-0.4 -0.1])` | 40 Hz, 100–200 ms: above 6 dB and ITPC above 0.8 |
| `_x05_band_power` | `runBandPower(4, {'Theta','Gamma'})` | gamma above 100 % |
| `_x06_erp_with_gamma` | `runERP(...)` | 15 epochs |

`testLFPTimeFrequencyInputChecks` checks the input handling:
- an unknown band name, fmax above Nyquist and channel 99 each return `false` without throwing;
- numeric bands take the matching table names.

## Verification done here

- `__parse_file__` passes in Octave 8 for all six `.m` files.
- `LFPFeaturesTest` was run in Octave through a scratch harness: a fake TestCase with `verify*` methods, a seeded `RandStream` shim and a `std(...,'omitnan')` shim. **All 15 pass.**
- MATLAB's random streams differ from the shim, so the statistical tests were repeated over **40 different realizations** of the demo noise.
  - Observed ranges: ERSP gamma 9.6–12.2 dB; ITPC gamma 0.967–0.987; theta ITPC late ≤ 0.57; theta CV ≤ 0.17; mean theta power / A² between 0.98 and 1.14; gamma band power +349 to +585 %.
  - The thresholds were set with margin from these ranges.
- **Unverified (needs CI):**
  - everything in the UI: layout, uitable behaviour including `Enable` and cell-edit reverts, `scroll` on a grid layout, the visual look of the new tabs;
  - the walkthrough test;
  - MATLAB Code Analyzer.

## References cited in headers

These are the only citations added, and I am certain of each:

- Welch PD (1967). The use of fast Fourier transform for the estimation of power spectra: a method based on time averaging over short, modified periodograms. *IEEE Trans Audio Electroacoust* 15(2):70–73.
- Tallon-Baudry C, Bertrand O, Delpuech C, Pernier J (1996). Stimulus specificity of phase-locked and non-phase-locked 40 Hz visual responses in human. *J Neurosci* 16(13):4240–4249. Covers Morlet wavelet power and the phase-locking factor (ITPC).
- Makeig S (1993). Auditory event-related dynamics of the EEG spectrum and effects of exposure to tones. *Electroencephalogr Clin Neurophysiol* 86(4):283–293. Covers ERSP.
- Pfurtscheller G, Lopes da Silva FH (1999). Event-related EEG/MEG synchronization and desynchronization: basic principles. *Clin Neurophysiol* 110(11):1842–1857. Covers band power as % change from a reference period.
- Mitzdorf U (1985). Current source-density method and application in cat cerebral cortex: investigation of evoked potentials and EEG phenomena. *Physiol Rev* 65(1):37–100. Covers CSD, in the `ERPAnalysis` header.

Needs reference (not cited):
- The ERSP status line gives a single-point ITPC chance level `sqrt(−ln 0.05 / N)`. This is the large-N Rayleigh approximation, p ≈ exp(−N·R²). Add a circular-statistics reference if it goes into the Help.

## Follow-ups for the lead

- TF results are not included in **Export ERP / CSD…**. Add them if batch processing needs them.
- Wire the demo into DemoData (see above), paste the Help text below, and add CHANGELOG entries.

## Ready-to-paste Help text (`apps/HelpApp.m`, `topicLFPAnalysis`)

Change the summary to:

```matlab
'Average the LFP around each stimulus (ERP), compute current source density (CSD) and analyse oscillations (spectrum, spectrogram, ERSP / ITPC, band power).'
```

Append to `t.quick`:

```matlab
'**6 Time–frequency**: choose the **Channel**, **Frequencies (Hz)** (lowest – highest), **Wavelet cycles**, **Epoch (s)** and **Baseline (s)**. The band table (delta 1–4, theta 4–8, alpha 8–13, beta 13–30, gamma 30–80 Hz) holds common conventions: edit the limits for your preparation and tick **Plot** for the bands to show.'
'Click **Spectrum** (power spectrum of the whole recording), **Spectrogram** (power over time with the stimuli marked), **ERSP / ITPC** (power change in dB and phase locking around each stimulus) and **Band power** (% change of each ticked band around the stimulus, mean ± SEM). Each opens its tab. ERSP and Band power use the stimulus onsets found with the ERP threshold (0.5 until you run the ERP).'
'**Try oscillation demo** (step 6) loads a demo with known theta and gamma oscillations and selects channel 4.'
```

Append to `t.demo`:

```matlab
'* **Oscillation demo** (**Try oscillation demo**): the same LFP plus **6 Hz theta** (40 µV, on every channel, not phase-locked to the stimuli) and a **40 Hz gamma burst** (10 µV, **50–250 ms after each stimulus**, **channels 3–5**, phase-locked). Channel 4 is chosen.'
'* **Spectrum**: 1/f background with a clear **peak at ~6 Hz** (theta) and a small bump near **40 Hz**.'
'* **Spectrogram** (2–80 Hz): a steady band at 6 Hz, and short 40 Hz patches just after each dashed stimulus line.'
'* **ERSP / ITPC** (2–80 Hz, 7 cycles, baseline −0.4 to −0.1 s): about **+10 to +12 dB at 36–44 Hz between 50 and 250 ms**, ITPC ≈ **0.97** there, and ≈ 0 dB before the stimulus and after ~0.3 s. The ERP itself (N1 / P2) adds a brief broadband increase with high ITPC in the first ~50 ms. On channel 8 (no gamma) there is no 40 Hz increase. 14 of the 15 stimuli are used (the last epoch would run past the end of the recording), and 13 at the lowest frequencies.'
'* **Band power**: **Gamma rises by roughly +350 to +600 %** at 0.1–0.2 s; **Theta stays flat** (~0 %, no stimulus modulation).'
```

Append to `t.outputs`:

```matlab
'Time–frequency tabs: Spectrum (Welch PSD, log–log, bands shaded), Spectrogram (STFT power in dB, dashed stimulus onsets), ERSP / ITPC (dB vs baseline on a blue–white–red scale centred at 0; ITPC 0–1), Band power (% change vs baseline, mean ± SEM per band)'
```

Append to `t.details`:

```matlab
'## Time–frequency'
'* **Spectrum**: Welch''s method, 2 s Hann segments with 50% overlap, each segment''s mean removed; density in units²/Hz, so the area under the spectrum equals the signal variance.'
'* **Spectrogram**: short-time Fourier transform, 0.5 s Hann windows, 90% overlap; power in dB.'
'* **ERSP / ITPC**: complex Morlet wavelets (unit energy; time resolution ≈ cycles / (2π·f) s). ERSP is 10·log10 of the trial-averaged power divided by the mean power in the baseline window; ITPC is the length of the mean unit phase vector across trials (0 = random phase, 1 = identical phase). At each frequency, trials whose wavelet would reach past the start or end of the recording are left out.'
'* **Band power**: band-pass filter plus Hilbert envelope (done with the FFT), power = envelope², then % change from the trial-averaged baseline. Trials closer to the recording edges than the filter''s settling time (about 1 s for delta / theta) are left out for that band.'
'* Band limits are conventions and vary between species, brain areas and labs; there is no single correct definition.'
```

Append to `t.trouble`:

```matlab
'"No stimulus onsets detected" in ERSP / ITPC or Band power', 'These use the ERP stimulus threshold and minimum ISI (0.5 and 0.5 s until the ERP has been run). Run the ERP (step 3) with a threshold that suits the Stimulus tab, then try again.'
'"The highest frequency must be below the Nyquist frequency"', 'Enter a highest frequency below half the LFP sampling rate (e.g. < 508 Hz for 1017 Hz data).'
'"The baseline window … lies outside the epoch window"', 'Keep Baseline (s) inside Epoch (s), e.g. epoch −0.5 to 1 s and baseline −0.4 to −0.1 s.'
'ERSP uses fewer trials at low frequencies, or low rows are blank', 'Low-frequency wavelets are long (3·cycles / (2π·f) s each side); trials whose wavelet would run past the recording start or end are left out at those frequencies. Raise the lowest frequency or use fewer cycles.'
'Band power tile says n is smaller for delta / theta, or "No epochs far enough from the recording edges"', 'The band filter needs about 1 s of data on each side of an epoch; trials near the start or end of the recording are left out for that band.'
'A band-table edit is undone', 'Limits must be numbers ≥ 0 with Low < High; the previous value is restored and the status bar says why.'
```

HelpApp "Demo files" table row, if the kind is wired into DemoData:

```matlab
'| demo_lfp_oscillations.mat | LFP Analysis (step 6) | demo_lfp.mat plus 6 Hz theta (40 µV, all channels) and a phase-locked 40 Hz burst (10 µV, 50–250 ms after each stimulus, channels 3–5) |'
```
