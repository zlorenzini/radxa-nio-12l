# APU Bring-Up Investigation Log (NIO 12L / MT8395)

This document records the end-to-end investigation for getting MediaTek APU inference running on Radxa NIO 12L in this repository.

## Scope

- Board: Radxa NIO 12L (MT8395 / Genio 1200)
- Host OS under test: Armbian 26.2.1 noble (Ubuntu 24.04 userspace)
- Goal: run inference on MediaTek APU using available/precompiled model paths

## Current Outcome

- We have a working local Python setup and helper scripts.
- We identified the real blocker: missing NeuroPilot userspace/config on the running noble system.
- We found a complete usable component set inside the extracted scarthgap Yocto image.

## What Was Added To This Repo

### Scripts

- `run-apu-demo.sh`
  - One-command demo wrapper.
  - Uses bundled repo prebuilts in `mtk-neuropilot-prebuilts`.
  - Prefers local `.venv` Python when available.
  - Performs backend probe and emits explicit failure text when APUSYS config is missing.

- `check-apu-env.sh`
  - Preflight checker for APU readiness.
  - Verifies tools, libs, `/etc/nhw`, `/etc/apusys/mt8195/nhw`, `/vendor/etc/armnn_app.config`, firmware paths, and backend probe result.

- `install-genio-neuropilot.sh`
  - Installer for official Genio Ubuntu package flow.
  - Includes apt lock-wait handling for `packagekitd` contention.
  - Includes codename guard and source cleanup for unsupported releases.

### Docs

- `docs/apu-quickstart.md`
  - Short path for running preflight and demo.
  - Documents Genio PPA package path and limitations.

### Git Ignore

Ignored large imported image folders and artifacts:

- `genio-classic-desktop-noble-emmc-20250926-1185/`
- `genio-g1200-evk-boot-assets-20250926-1185/`
- `scarthgap_k6.6_v25.1.1_genio-1200-evk-ufs_private_260316022635/`
- Generated extraction artifacts (`*.raw.img`, `*.ext4`)

## Key Findings By Source

### 1) LiteRT MediaTek docs

- LiteRT has MediaTek NPU support via `CompiledModel` APIs.
- But practical support matrix and flow do not directly solve MT8395/NIO bring-up here.
- For this board/repo, direct NeuroPilot runtime path is currently the practical route.

### 2) This repo's prebuilt NeuroPilot content

- `mtk-neuropilot-prebuilts` includes tools/libs/models/samples.
- Initial demo failed not due to Python, but due to APUSYS runtime config:
  - `Can't open config file`
  - `ERROR: Getting configuration data failed.`

### 3) Genio Ubuntu package docs

Official docs specify:

- Add PPA: `ppa:mediatek-genio/genio-public`
- Install for Genio 1200:
  - `mediatek-apusys-firmware-genio1200`
  - `mediatek-libneuron`
  - `mediatek-neuron-utils`
  - `mediatek-libneuron-dev`

Observed on board:

- Running system is `noble`.
- `genio-public` PPA currently publishes `jammy` packages.
- Result: no `Release` for `noble`; apt rejects source.

### 4) Imported noble Genio image content

From extracted `ubuntu.img` + boot assets:

- Firmware for APUSYS exists (for example `apusys.sig.img`, `cam_vpu*.img`).
- NeuroPilot userspace/config not present in rootfs:
  - missing `ncc-tflite`, `neuronrt`, `runtime_api_sample`
  - missing `/etc/nhw`, `/etc/apusys/mt8195/nhw`, `/vendor/etc/armnn_app.config`

### 5) Extracted scarthgap Yocto image content (critical)

From mounted rootfs of `rity-demo-image-...wic.img`:

Found and usable:

- Tools:
  - `/usr/sbin/ncc-tflite`
  - `/usr/sbin/neuronrt`
  - `/usr/sbin/runtime_api_sample`
- Config:
  - `/etc/apusys/mt8195/nhw`
  - `/etc/nhw` symlink -> `apusys/mt8195/nhw`
- Runtime libs and middleware:
  - `libneuronusdk_runtime.mtk.so.6.3.3`
  - `libneuronusdk_adapter.mtk.so.6.3.3`
  - `libapu_mdw*.so`
  - `libmdla_ut*.so`
  - `libvpu5*.so`
  - `libapusys_edma*.so`
- Firmware:
  - `/usr/lib/firmware/mediatek/mt8395/apusys.sig.img`
  - `/usr/lib/firmware/mediatek/mt8395/cam_vpu1.img` (+ vpu2/vpu3)

Also confirmed in manifest:

- `mtk-apusys-driver`
- `mtk-apusys-firmware`
- `mtk-apusys-middleware`
- `mtk-apusys-tools`
- `neuropilot-bin`
- `packagegroup-rity-mtk-neuropilot`

Still not found there:

- `armnn_app.config` (not observed in mounted scarthgap rootfs during search)

## Practical Interpretation

- The APU kernel/firmware side is mostly present.
- The runtime failure is userspace/config availability and layout.
- The scarthgap image contains the strongest known-good userspace set for this hardware.

## Known Failure Modes Encountered

- `apt` lock contention from `packagekitd`.
- Unsupported PPA suite (`noble`) for Genio public archive.
- Misleading downstream crash in sample script when no backend is available.

## Recommended Next Step (Operational)

Use scarthgap as the source of truth for userspace components and import required files to the running system with backup and verification:

1. Copy tools into `/usr/sbin`.
2. Copy libs into `/usr/lib` (or matched runtime lib path).
3. Copy `/etc/apusys/mt8195/nhw` and ensure `/etc/nhw` symlink exists.
4. Ensure firmware files exist under `/lib/firmware/mediatek/mt8395/` or `/usr/lib/firmware/...` based on kernel lookup path.
5. Re-run:
   - `./check-apu-env.sh`
   - `./run-apu-demo.sh`

If backend probe still fails after this, capture exact `ncc-tflite --arch=?` output and inspect runtime search paths with `strace` (file-open failures).

## Command Outputs Worth Remembering

- Earlier failing probe:
  - `Can't open config file`
  - `ERROR: Getting configuration data failed.`
- PPA mismatch on noble:
  - `... noble Release does not have a Release file`

## Status Snapshot

- Python/venv: OK
- Local helper scripts: OK
- APU inference end-to-end on current noble image: not yet complete
- Best available component source: extracted scarthgap Yocto rootfs
