# Core imaging utilities

Used by **ROI / Coregistered Image Analysis** for 2P/multiphoton, fluorescence, blood flow, and vessel imaging.

## Intensity and ROI

- **imageToGrayscale256** – Convert image or stack to 256-level B&W (uint8). Handles RGB, single/double, stacks.
- **roiIntensityOverTime** – Mean intensity in ROI per frame (brightness time series).
- **roiMovement** – Movement in ROI: `'diff'` = mean absolute frame difference, `'variance'` = variance in ROI per frame.

## Fluorescence (gCaMP, etc.)

- **deltaFOverF** – (F − F0)/F0 in ROI. Baseline: `'first'` (mean of first N frames), `'percentile'`, `'rolling'`, or `'mean'`.

## Speed, flow, propagation

- **roiFlowSpeed** – Mean magnitude of frame-to-frame change in ROI (flow/speed proxy for blood flow, 2P).
- **kymograph** – Extract space-time image along a line (for propagation, flow direction).
- **propagationSpeedFromKymograph** – Estimate propagation speed from kymograph (slope of ridge).

## Vessel diameter

- **vesselDiameterFromLine** – Intensity profile along a line perpendicular to vessel; diameter as FWHM or threshold width per frame (fluorescence or multiphoton).

## Preprocessing

- **imageStackSmooth** – Gaussian or median smooth per frame.
- **imageStackNormalize** – Normalize stack to 0–1 (min/max, percentile, or per-frame).
