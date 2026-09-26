# Handoff (2026-09-26, session 5, end)

Working branch: `claude/admiring-cori-52ekpa` (= main 4852898 + EEG roadmap commit fd9d13d + merge 74547b9).
Owner decision: `docs/dev/` stays out of `main`. **Delete this file before merging the next PR.**

## Done this session
- PR #9 (website: Histology, CSD methods, repeated-measures walkthroughs) squash-merged into `main`
  as `4852898` after MATLAB CI green; owner confirmed the merge ("go").
  Cloudflare deploy of `main` NOT verified (the site is not reachable from the container; the
  workers.dev URL is unknown). Ask the owner to check the site, or look for the Cloudflare
  check on commit 4852898.
- Owner asked for EEG. Plan agreed and written in `ROADMAP.md` ("EEG (planned)" section, pushed):
  general (any electrode convention: 10-20/10-10/10-5, BioSemi, EGI, custom files, rodent bregma),
  most-used systems first, data already cleaned in MATLAB first. 7 steps, one PR each.
- Octave 8.4 installs in the container with
  `apt-get update && apt-get install -y --no-install-recommends octave` (~5 min).
  Octave has no `RandStream`, which the demos use: new demo code should use it the same way (MATLAB CI
  is the reference); for local checks, run the pure-parsing parts in Octave.

## Next: EEG step 1 (not started; no files written)
Scope: data model + MATLAB importers (EEGLAB, FieldTrip, plain .mat) + synthetic demo + tests.
No window yet (step 2). Update ROADMAP step 1 to 🔨 and add a CHANGELOG "Unreleased" entry.

Design worked out (follow the style of `core/io/EphysSource.m` and `tests/FormatsFeaturesTest.m`):
- `core/io/EEGSource.m` (static): `formats()`, `detect(path)`, `open(path, fmt)`, `make(...)`,
  `validate(eeg)`, `describeHistory(eeg)` (plain-language lines), `guessMatrixMap(path)`
  (variables + suggested mapping, backend for the plain-.mat form in step 2).
- Common struct: data chan x samples x trials (µV; if values look like volts, convert and say so
  in plain words), fs, times (s; epoch time for trials, from 0 for continuous), labels, chanlocs
  (as read + coordSystem tag, e.g. 'EEGLAB (x = nose)', 'FieldTrip', 'bregma (mm)'; conversion to
  one orientation is step 3), trials.condition (per trial) + conditions list, events (continuous),
  reference, history (plain lines), source/format/file, isEpoched.
- `readEEGLAB.m` / `writeEEGLAB.m`: .set is a MAT file holding either variable `EEG` or the EEG
  fields at top level (newer pop_saveset); EEG.data numeric or a .fdt file name (float32 LE,
  nbchan x pnts*trials). Condition per epoch = type of the event at time 0 of that epoch
  (zero index = round(-xmin*srate)+1). chanlocs labels/X/Y/Z/theta/radius. History parsed from
  EEG.history: pop_eegfiltnew (locutoff/hicutoff), pop_reref, pop_subcomp (components),
  pop_rejepoch (count), pop_interp (channel index -> label), pop_resample; unknown lines shown raw.
- `readFieldTrip.m` / `writeFieldTrip.m`: raw (label, trial{}, time{}, fsample, trialinfo,
  sampleinfo, elec with coordsys/unit) and timelock (avg or trial with dimord). History from the
  cfg.previous chain: bpfilter/bpfreq, hpfilter/hpfreq, lpfilter/lpfreq, reref/refchannel,
  resamplefs, component (ft_rejectcomponent), badchannel/missingchannel (ft_channelrepair),
  artfctdef.*.artifact rows (rejected trials); function name from cfg.version.name if present.
- `readEEGMatrix.m`: plain .mat with a map (data var, fs number or var, dim order, labels var,
  times var or tStart, conditions var, unit).
- `core/demo/demoEEG.m`: deterministic (RandStream). Scalp: 8 participants (option for fewer in
  tests), 32 channels (actiCAP-32 names: Fp1 Fp2 F7 F3 Fz F4 F8 FC5 FC1 FC2 FC6 T7 C3 Cz C4 T8 TP9
  CP5 CP1 CP2 CP6 TP10 P7 P3 Pz P4 P8 PO9 O1 Oz O2 PO10) with positions from spherical angles,
  250 Hz, epochs -0.2..0.8 s, conditions Standard / Target / Novel (oddball), N1 ~100 ms at Cz,
  P300 ~350 ms at Pz (Target > Novel > Standard), 10 Hz occipital alpha with random phase, 1/f +
  white noise, some trials already rejected; history lines for filter 0.1-30 Hz, average
  reference, ICA components 1 and 3 removed, trials rejected, T7 interpolated. Rodent: continuous,
  4 skull electrodes with bregma (mm) coordinates, 1000 Hz, flash events every 2 s, VEP at V1.
  Write every case as EEGLAB (.set inline and .set + .fdt), FieldTrip and plain .mat; single precision.
- `tests/EEGFormatsTest.m`: each importer returns the same data (single precision), conditions,
  events, labels, positions and history sentences; hand-built files from the published layouts;
  clear errors (missing .fdt, wrong sizes, unknown variables). Add `core/io` is already on the path.

## Working rules learned
- Commit identity = owner (CLAUDE.md). The stop hook asking for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: after a squash merge, merge `main` into the branch (no content change).
- The auto-mode permission check blocks merges (and cleanup after them) unless the owner says
  plainly in the chat to merge. Ask for an explicit "merge PR #N".
- Keep CI minutes low: `**.md`, `docs/**` and `website/**` changes do not start the MATLAB CI.

## Open questions for the owner
- v0.4.0 release (still unanswered).
- Two small Histology app fixes (session pixel-size note says "Typed by you." after reopening;
  Help/website say 2.7 px and "nothing to warn about", the app shows 2.6 px and a "Check" row).
- Which EEG cleaning tools / systems the lab uses (owner said: general first, specialise later).
