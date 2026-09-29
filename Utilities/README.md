# Utilities

Third-party MATLAB utilities live here. They are **not redistributed**
in this repo because they have their own license and authorship — drop
them in locally as documented below.

## TDTMatlabSDK/

Required only for `Extract Ephys Data` (loading TDT tank files).

- **Where to get it:** [tdt.com/support/matlab-sdk](https://www.tdt.com/support/matlab-sdk/)
- **Where to put it:** unzip into `Utilities/TDTMatlabSDK/` so the
  inner folder contains `TDTSDK/`, `Examples/`, etc.
- **Tracked?** No. The folder is in `.gitignore`.

If you don't process TDT data, you can ignore this entirely — the LDF,
ROI imaging, and signal characterization apps work without the SDK.

See the project [README](../README.md#install-the-tdt-sdk) for the full
install walk-through.
