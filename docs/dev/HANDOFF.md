# Handoff (2026-09-26, session 8, end: context budget reached)

Working branch: `claude/admiring-cori-52ekpa` (= main ecd76ff, v0.4.0, + merge commit + BrainVision draft).
Owner decision: `docs/dev/` stays out of `main`. **Delete this file before merging the next PR.**

## Done (this session)
- EEG window CI fixes and screenshot review (plot clearing, y range, measure row order), Histology fixes.
- PR #10 merged (squash, ecd76ff): EEG steps 1-2. **v0.4.0 released**
  (https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.4.0).
- Screenshots workflow has a `source` input (make screenshots from an unmerged branch; run with
  include_all to get them committed under review-screens/ — artifact downloads are blocked in this
  environment; remove review-screens/ afterwards).

## Owner decisions (this session)
- EEG statistics stay only inside the EEG window.
- Keep EEG compatible with many systems; the owner's lab uses "Brain Lab" (asked whether that means
  Brain Products / BrainVision; the owner answered "Go", taken as yes — confirm when convenient).

## In flight: NEW STRAND "EEG raw formats, BrainVision first" (next EEG step, ahead of layouts)
- `core/io/readBrainVision.m` and `core/io/writeBrainVision.m` written (committed with [skip ci],
  **untested**). Reader: .vhdr v1 / v2 (UTF-8), binary INT_16 / UINT_16 / INT_32 / FLOAT_32 / 64,
  big-endian flag, ASCII (decimal comma, SkipLines / SkipColumns), multiplexed / vectorized,
  resolution and unit (nV / uV / mV / V) per channel, markers (.vmrk; 'S  1' -> 'S 1'), continuous
  events, Analyzer segments (MARKERBASED / FIXTIME, Time 0, condition = marker at time 0, Averaged),
  [Coordinates] radius/theta/phi -> x right, y nose, z up, reference from [Channel Infos], Recorder
  [Comment] amplifier / software filter tables -> notes / history. Writer: float32 / int16 / int32,
  orientation, positions, reference, comment, version 1 / 2.
- First Octave run failed: Octave's `regexp` rejects Latin-1 bytes > 127 as invalid UTF-8 in
  `readIni` (the µ of "µV"). MATLAB is fine with char(181); for Octave checks, either decode
  Latin-1 bytes to Unicode chars (`char(double(b))` already is; the issue is Octave's UTF-8 regexp),
  or test in Octave with ASCII 'uV' units. Test script: see the "Next" list.

## Next
1. Make the round trip pass locally (Octave, `apt-get install -y --no-install-recommends octave`):
   continuous INT_16 with events and a Recorder [Comment] table; segmented float32 with positions,
   version 2, vectorized. Check positions: Fpz (0,1,0) -> 1,90,90; Fp1 -> theta -90, phi -72;
   Oz -> 1,90,-90; Cz -> 1,0,0.
2. Wire in: `EEGSource.formats/detect/open` ('brainvision'; .vhdr; .vmrk / .eeg -> plain error
   pointing to the .vhdr), EEG window load filter `*.set;*.mat;*.vhdr` and tooltip text, Help
   (`topicEEGAnalysis` inputs), `demoEEG` writes `brainvision` for scalp (segmented, float32,
   posRAS) and rodent (continuous, INT_16, 0.1 uV) + `allExist` list + cacheVersion 2,
   `EEGFormatsTest` (demo agreement, hand-built files: 'S  1' markers, ASCII decimal comma,
   big-endian, missing .eeg, name with \1, mV unit, averaged, bad intervals), `testDetect` format
   list, ROADMAP (BrainVision row), CHANGELOG [Unreleased], tests/README.
3. One CI run for all of it; then PR when the owner asks.

## Open questions for the owner
- "Brain Lab" = Brain Products (BrainVision Recorder / Analyzer)? Continuous Recorder files,
  Analyzer exports, or both? A sample .vhdr/.vmrk (no data needed) would help test real headers.

## Working rules learned
- Commit identity = owner (CLAUDE.md). The stop hook asking for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: after a squash merge, merge `main` into the branch (no content change).
- Keep CI minutes low: `**.md`, `docs/**` and `website/**` changes do not start the MATLAB CI;
  `[skip ci]` in a commit message skips it too.
- Artifact downloads (Azure blob hosts) are blocked; use the screenshots workflow with a `source`.
- `send_later` / new sessions may fail here: session lineage depth limit reached.
