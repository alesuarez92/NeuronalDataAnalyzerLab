# Product vision and feature set

This document records the full scope of what this app is intended to do: **current** (MATLAB toolbox) and **future** (web app and beyond). Use it as the single reference for “all the functionalities I want this app to have.”

---

## Vision (high level)

- **Goal:** A single, powerful tool for experimental neuroscientists to **process**, **analyze**, and **visualize** multimodal experimental data without spending time on scripting.
- **UX:** Interactive, instructive (guided workflows, tooltips, help), and user-friendly, but very powerful under the hood.
- **Future delivery:** Web app (React/Django) sold by **membership**; data assumed in CSV (with format conversion from major acquisition systems later).
- **Long-term:** Coregistration and analysis of **fMRI / PET / SPECT** imaging, plus **AI-based classifiers**, **diagnostics**, and more.

---

## Data modalities (current and planned)

| Modality | Status | Notes |
|----------|--------|------|
| **LDF (Laser Doppler Flowmetry)** | ✅ In MATLAB | Extract → Process (filter, segment) → Grand average; signal characterization. |
| **Speckle flowmetry** | Planned | Same family as LDF; add when needed. |
| **Electrophysiology (single/multi-electrode)** | ✅ In MATLAB | LFP, MUA; TDT tank load; ERP, CSD; spike sorting. |
| **EEG** | Planned | Add to web app (and optionally MATLAB). |
| **EMG** | Planned | Add to web app (and optionally MATLAB). |
| **Generic time series** | ✅ In MATLAB | Signal characterization (t, y). |
| **Images and time series** | Planned | Broader support in web app. |
| **Coregistered images / ROI** | ✅ In MATLAB | ROI/line: brightness, movement, speed, ΔF/F, kymograph, vessel diameter; B&W 256, smooth, normalize. |
| **Fluorescence (gCaMP, etc.)** | ✅ In MATLAB | ΔF/F in ROI; 256-level B&W; intensity and propagation. |
| **Blood flow / 2P / multiphoton** | ✅ In MATLAB | Speed (flow) in ROI; kymograph; propagation speed; vessel diameter from line. |
| **Ultrasound** | Planned | Future modality. |
| **Microscopy** | Planned | Future modality. |
| **fMRI** | Planned | Import, coregistration, overlay, QC. |
| **PET** | Planned | Import, coregistration, overlay, QC. |
| **SPECT** | Planned | Import, coregistration, overlay, QC. |

---

## Current MATLAB toolbox – feature list

- **Main launcher (Main.m):** Two sections – (1) Filtering & signal processing, (2) Signal characterization; project bar (Import/Export dirs); Help.
- **LDF pipeline:**  
  Extract LDF (load .mat → crop → save) → Process LDF (filter, downsample, segment by onsets, average, save) → Average LDF Viewer (grand average ± baseline).
- **Ephys pipeline:**  
  Extract Ephys (TDT tank → LFP/MUA save) → LFP Analysis (ERP, CSD) → MUA Analysis (segment, spike sort, rate).
- **Signal characterization:**  
  Load processed data (LDF segments, ERP, or t/y) → set t0 and baseline → select features (peak latency, onset delay, FWHM, AUC±, rise/decay, peak amplitude, integral) → extract → table → export CSV or .mat.
- **Imaging / ROI analysis (coregistered images):**  
  Load image stack → define **ROI** (rectangle) or **line** (for kymograph/vessel) → optional **B&W 256**, **smooth**, **normalize** → choose analysis: **Brightness**, **Movement**, **Both**, **ΔF/F (gCaMP)**, **Speed (flow)**, **Kymograph**, **Vessel diameter** → plot and (optionally) export.
- **Image processing tools:**  
  **B&W 256** (fluorescence); **smooth** (Gaussian/median); **normalize** (0–1); **ROI intensity** and **movement**; **ΔF/F** with baseline (first frames, percentile, rolling); **speed/flow** in ROI (frame-diff magnitude); **kymograph** along line and **propagation speed**; **vessel diameter** from line (FWHM or threshold) for fluorescence/multiphoton.
- **Help:** Tabbed help from docs/.
- **Project:** Set Import/Export directories (project scope for load/save).

---

## Future web app (React/Django) – feature list

- Everything above, reimplemented with **CSV as primary input** (and optional format conversion from acquisition systems).
- **Membership / subscription:** Free tier vs paid (full pipelines, export, storage, later imaging/AI).
- **Projects and storage:** User projects; upload/list/download files; run pipelines (Celery); results and export.
- **Modular structure:** Shared core (data I/O, validation, signals, features, export); modality modules (LDF, Ephys, characterization, then EEG, EMG, etc.).
- **Imaging (later phase):** fMRI, PET, SPECT – import, coregistration, overlay, basic QC.
- **AI (later phase):** Classifiers, diagnostics, automated QC, report generation.

---

## Feature summary (checklist style)

**Already in MATLAB**

- [x] LDF: load, crop, save; filter/downsample; segment by stimulus; grand average; baseline correction.
- [x] LDF: signal characterization (all 9 features) and export CSV/.mat.
- [x] Ephys: TDT load; LFP/MUA extract and save; ERP (pre/post, threshold, min ISI); CSD.
- [x] MUA: segment by onsets; spike detection and clustering; spike rate.
- [x] Project dirs (Import/Export); Help.
- [x] Validation (LDF struct, crop range); core processing (crop, filter, segment, features).

**Planned (web app, same workflows)**

- [ ] CSV in/out; format conversion from acquisition systems.
- [ ] Projects, storage, pipelines (async jobs).
- [ ] LDF + characterization + Ephys in browser; membership gate.

**Planned (more modalities)**

- [ ] EEG, EMG.
- [ ] Ultrasound, microscopy; generic images/time series.

**In MATLAB (imaging / ROI)**

- [x] ROI analysis: brightness, movement, both; optional B&W 256, smooth, normalize.
- [x] ΔF/F (gCaMP): (F−F0)/F0 in ROI; baseline = first N frames, percentile, rolling, or mean.
- [x] Speed (flow): frame-to-frame change magnitude in ROI (blood flow, 2P).
- [x] Kymograph: space-time image along a line; propagation visualization.
- [x] Propagation speed: from kymograph (ridge slope).
- [x] Vessel diameter: from line perpendicular to vessel (FWHM or threshold) over time.
- [x] Fluorescence: 256-level B&W; intensity in ROI; vessel diameter from fluorescence/multiphoton.

**Planned (imaging)**

- [ ] fMRI, PET, SPECT: import, coregistration, overlay, QC.

**Planned (AI)**

- [ ] AI-based classifiers and diagnostics; automated QC; reports.

---

*This file is the single place that lists all functionalities you want the app to have. Update it as the vision or priorities change.*
