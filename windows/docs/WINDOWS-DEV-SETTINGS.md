# WINDOWS-DEV-SETTINGS.md — Windows security settings for a C build environment

Freshly compiled executables are unsigned.  On a default Windows 10/11
installation several independent security mechanisms can block them from
running — each managed separately, each with its own fix.  This page
covers the three most common offenders and how to configure them for a
developer workstation without weakening protection against real threats.

The symptoms are unmistakeable: a newly built `.exe` or `ctest` process
fails to start with a message like

```
An Application Control policy has blocked this file.
```
or PowerShell's
```
ResourceUnavailable: An error occurred trying to start process '...'
```

If you see either of these, work through the sections below.

---

## 1. Smart App Control (Windows 11)

**What it is.** Smart App Control is a Windows 11 feature that blocks
execution of any program it cannot verify — either by checking a
Microsoft cloud reputation service or by confirming the binary is
signed.  In *Evaluating* mode it learns from your usage; in *On* mode
it blocks anything unsigned it hasn't seen before.  There is no
per-folder or per-process exception list.

**Impact on dev builds.** Every `.exe` produced by a local build is
unsigned and unknown to the reputation service, so Smart App Control
will block it the first time it is run.  This breaks `ctest`, the probe
exe, and every tool you build.

**Fix.** The only option is to turn it off.

Via the UI:
```
Windows Security
  → App & browser control
  → Smart App Control settings
  → Off
```

Or from an **elevated** PowerShell prompt:
```powershell
.\scripts\disable-sac.ps1
```

To check the current state (no elevation required):
```powershell
.\scripts\check-dev-security.ps1
```

> **Note:** Smart App Control cannot be re-enabled without resetting the
> PC.  On a dedicated development machine, leaving it off permanently is
> the standard practice.  On a shared or corporate machine, discuss with
> your IT department before changing this setting.

---

## 2. Windows Defender real-time protection — folder exclusions

Even with Smart App Control off, Defender's real-time scanner may
quarantine or delay execution of a newly compiled file before it has
been scanned.  The reliable fix is to tell Defender to skip your source
and build trees entirely.

**Folders to exclude.**  Add each of these as a folder exclusion:

| Folder to add | Why |
|---|---|
| Your source root (the directory containing the cloned repos) | Covers build output under every project |
| `%TEMP%` | CMake uses temp directories during configure |
| Visual Studio's intermediate output directories (under your source root) | Covered by the source root exclusion above |

**How to add a folder exclusion.**

From an **elevated** PowerShell prompt:
```powershell
.\scripts\add-defender-exclusion.ps1 C:\usr\local\src
```

To check whether a path is already excluded (no elevation required):
```powershell
.\scripts\check-dev-security.ps1 C:\usr\local\src
```

Or via the UI:
```
Windows Security
  → Virus & threat protection
  → Manage settings  (under "Virus & threat protection settings")
  → Exclusions
  → Add or remove exclusions
  → Add an exclusion → Folder
```

Add your source root (e.g. the drive or directory where you clone all
your development repositories).  A single top-level folder covers every
project beneath it without needing per-project maintenance.

> **Scope vs. risk.** Excluding your source tree from real-time scanning
> does not disable Defender for the rest of the machine.  Downloads,
> email attachments, browser activity, and all other paths remain fully
> protected.  The exclusion only affects files inside the named folder.

---

## 3. Third-party endpoint protection — Acronis True Image / Cyber Protect

Acronis products include an **Active Protection** module that uses
behavioural heuristics to detect ransomware.  One of those heuristics
is "a process is rapidly creating new executable files" — which is
exactly what a compiler toolchain does.  The result is that MSBuild,
`cl.exe`, or the freshly produced `.exe` is silently blocked or
quarantined.

**Symptoms specific to Acronis.** The build may appear to succeed but
the output `.exe` cannot be launched; or the build itself stalls at
link time with a file-access error.

**Fix.** Add your source root and the Visual Studio toolchain to
Acronis's trusted paths or trusted processes list.

Acronis True Image / Cyber Protect (exact UI varies by version):

```
Acronis True Image / Cyber Protect Home
  → Protection
  → Active Protection
  → Settings
  → Trusted processes  (or Trusted folders / Allowed list)
```

Add as **trusted folders**:
- Your source root
- The Visual Studio installation directory (typically under
  `%ProgramFiles%\Microsoft Visual Studio\`)

Add as **trusted processes** (alternative or complementary):
- `cl.exe` — the MSVC C/C++ compiler
- `link.exe` — the MSVC linker
- `MSBuild.exe` — the build orchestrator
- `cmake.exe` — CMake
- `ctest.exe` — the CTest runner

> If Acronis is managed by a corporate policy, contact your IT
> administrator for the correct procedure.

---

## 4. Other endpoint protection products

The same pattern applies to any behavioural AV or EDR product
(CrowdStrike Falcon, Sophos, ESET, Malwarebytes, etc.).  The
exclusion mechanism differs by product, but the things to whitelist
are always the same:

- Your source/build root directory (folder exclusion)
- The Visual Studio and Windows SDK directories under `%ProgramFiles%`
- Optionally, the compiler and linker executables themselves (process exclusion)

Consult your product's documentation for "developer workstation
exclusions" — most vendors publish a guide for exactly this scenario.

---

## 5. Verifying the fix

After applying the relevant settings above, run a freshly built
executable directly:

```powershell
.\build\Release\ftdi-rebind-probe.exe
```

Expected output (Phase 0 probe):

```
libwdi v1.5.0  wdf_version=1011  strerror(0)=Success
```

Then confirm `ctest` can launch test processes:

```powershell
ctest --test-dir build -C Release --output-on-failure
```

All tests should run and either pass or fail on their own logic — no
"BAD_COMMAND" or "Process not started" errors.

---

## Summary

| Mechanism | Location | Action |
|---|---|---|
| Smart App Control | Windows Security → App & browser control | Set to **Off** |
| Defender real-time | Windows Security → Virus & threat protection → Exclusions | Add your source root as a folder exclusion |
| Acronis Active Protection | Acronis → Protection → Active Protection | Add source root + VS dirs as trusted |
| Other AV/EDR | Product-specific exclusions UI | Add source root + VS/SDK dirs |

You need to address each mechanism independently — fixing one does not
fix the others.
