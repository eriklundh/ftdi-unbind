# PI4-TESTRUNNER.md — a Raspberry Pi 4 as the shelf HIL test station

Decision record + setup pointers for running the hardware-in-the-loop
(HIL) test station on a **Raspberry Pi 4** instead of a Pi 5. Written
2026-06-12, when Pi 5 prices spiked with the RAM shortage and the
question became: is a Pi 4 good enough, or should the rigs hang off a VM
with USB passthrough?

Short version: **a Pi 4 (4 GB+) is comfortably sufficient, and beats the
VM alternative in exactly the dimension that matters** — being a
known-good *physical* USB environment.

## What the station does

One small computer on a shelf, with two USB full-speed rig devices
attached, running a GitLab runner (shell executor) that serves **two
pipelines**:

| Pipeline | Jobs | Runner tag | Rig device |
|---|---|---|---|
| this repo (`ftdi-unbind`) | `diagnose`, `bind-unbind-cycle` | `rpi5` | FT231X loopback plug (0403:6015) |
| `unified-serial-term` | `terminal-app:test:hw`, `ftdi-driver:test:hw` (the `release-hw-*` production gate) | `hil-hardware` | both plugs |

The runner makes **outbound** connections to the GitLab instance only —
the station needs no inbound access and can sit on an internal network
segment. That is the designed topology: CI jobs are how code reaches the
hardware, not SSH.

## Why a Pi 4 is sufficient

- **The USB workload is tiny.** Both rig devices are USB *full-speed*
  (12 Mbps): an FT231X and a Pico CDC. The suites top out at 921600 baud
  and a 4 KB loopback burst. Nothing is bandwidth- or latency-critical.
- **The CPU workload is moderate and not time-critical.** Measured on the
  Pi 5 (2026-06-12): preflight ≈ 25 s, Playwright 57 tests ≈ 57 s, plus
  `npm ci`; a full hw job lands at ~3–4 minutes. A Pi 4 is roughly 2–3×
  slower, so expect ~8–10 minutes per job — irrelevant for a release gate
  that runs a few times a week.
- **USB controller maturity is a wash or better.** The Pi 4's VL805
  controller is old and well-exercised. The one physical-layer failure in
  this rig's history was on the *Pi 5* (its rightmost ports: I/O error →
  device drops off the bus → no re-enumeration; see the troubleshooting
  notes linked below). Label which ports the rigs use regardless.

Hardware checklist for the shelf unit:

- **RAM:** 4 GB minimum, 8 GB comfortable (headless chromium + vitest is
  the peak consumer).
- **Storage:** CI runs `npm ci` every job — many small writes. Use a
  quality SD card or, better, a small USB SSD.
- **Power:** the official PSU; the two rig plugs draw almost nothing, but
  chromium spikes the SoC.
- **Remote rescue:** install [`uhubctl`](https://github.com/mvp/uhubctl).
  On a Pi 4 VBUS switching is ganged (all ports toggle together), which
  is fine for a two-plug rig: it is a remote "replug everything" for a
  wedged device — the Pico CDC firmware currently has **no watchdog** and
  stays dead after a crash until power-cycled.

## Why not USB passthrough to a VM

Considered and rejected (2026-06-12):

- These test suites deliberately do the things virtual xHCI handles
  worst: sysfs driver unbind/rebind cycles, devices dropping off the bus
  and re-enumerating, raw libusb claims. Passthrough usually copes —
  "usually" is the problem.
- After any failure you must first rule out passthrough artifacts before
  trusting the result. The station's entire purpose is to *remove*
  ambiguity below the code under test.
- A wedged passthrough often needs VM-level intervention; VBUS
  power-cycling from inside a guest is impossible.
- A bare Pi keeps the network story clean: outbound HTTPS to GitLab,
  nothing else, no shared VM host bridging network segments.

## Setup — follow the existing runner doc

The full installation guide was written for the Pi 5 but applies to a
Pi 4 unchanged (same Raspberry Pi OS Trixie / Debian 13 arm64, same apt
runner install, same provisioning):

> `unified-serial-term` repo: `hil-preflight/rpi5-gitlab-runner-setup.md`
> (sibling checkout: `../../unified-serial-term/hil-preflight/rpi5-gitlab-runner-setup.md`)

Pay particular attention to:

- **§7 Register with GitLab — runner tags.** Both tags are required:
  `hil-hardware` (the `unified-serial-term` hw gate selects on it; a
  runner without it stalls `release-hw-*` pipelines forever) and `rpi5`
  (this repo's CI selects on it — keep the tag even on Pi 4 hardware, or
  retag this repo's `.gitlab-ci.yml` in the same change).
- **§8 Provision for the unified-serial-term hw jobs.** The udev rule
  giving `plugdev` raw-USB access to the FTDI plug (pyftdi/node-usb need
  `/dev/bus/usb`, which `dialout` does not cover) and the Playwright
  chromium OS libraries.
- **§Troubleshooting.** Field notes from the first hw-stage runs: flaky
  USB ports symptom escalation, Pico rig recovery (BOOTSEL gotcha, UF2
  reflash), and the stuck-`pending` pipeline gotcha.

Related reading:

- `unified-serial-term` repo: `pico-cdc-test-rig/CLAUDE.md` §"Hardening
  backlog" — the planned RP2040 watchdog that would make the station
  fully self-recovering.
- `unified-serial-term` repo: `hil-preflight/CLAUDE.md` — what preflight
  verifies and how the two rig suites fit together.
- This repo: `README.md` — the diagnosis scripts the `diagnose` CI job
  exercises against the same plug.
