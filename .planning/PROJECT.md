# haltune - LinuxCNC HAL Manager

## What This Is

A TUI-based LinuxCNC HAL manager written in Zig, providing real-time inspection and manipulation of HAL components (pins, signals, parameters, components). Includes workflow-specific plugins for machine setup tasks like velocity testing, trapvel profiling, and PID tuning. Works with standard LinuxCNC installations and has enhanced awareness for the riocore framework.

## Core Value

Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] **HAL Inspector Core**: Browse and manipulate all HAL components (pins, signals, parameters, components) in real-time with a structured TUI interface
- [ ] **LinuxCNC Integration**: Wrap LinuxCNC HAL and C APIs via Zig FFI layer for direct communication with the running HAL system
- [ ] **Riocore Awareness**: Detect and display riocore configuration context (view-only) when riocore framework is present
- [ ] **Velocity Tester Plugin**: Test stepper velocity limits in real-time to determine feasible operating ranges
- [ ] **Trapvel Plugin**: Single axis movements with ramped velocity profiles using trapvel.comp for axis characterization
- [ ] **PID Plugin**: Discover PID components in HAL and provide tuning interface with real-time parameter adjustment
- [ ] **Config Persistence**: Load and save HAL parameter sets for different machine configurations
- [ ] **TUX Framework**: VAxis-based TUI with responsive interface for Raspberry Pi 5 deployment

### Out of Scope

- **Riocore config editing** — riocore config is view-only in v1; edits go through rio-setup (prevents config drift)
- **FPGA manipulation** — FPGA programming is outside scope; HAL integration focuses on software layer
- **Multi-machine support** — v1 assumes single LinuxCNC instance on local machine
- **Remote HAL access** — no network HAL manipulation; runs directly on machine PC
- **Motion program control** — not a G-code sender or motion controller; focuses on HAL/config layer
- **Real-time plotting** — no oscilloscope-style signal visualization in v1 (may come in v2)

## Context

**LinuxCNC HAL Architecture**: LinuxCNC uses the Hardware Abstraction Layer (HAL) to connect software components to hardware. Components expose pins (input/output), parameters (configurable values), and signals (wires connecting pins). Current manipulation happens via `halcmd` CLI which is cryptic and lacks workflow guidance.

**Riocore Framework**: Riocore is a framework for building FPGA-based I/O interfaces for LinuxCNC. It uses a `rio-setup` config file as the source of truth, generating FPGA bitstreams and .ini/.hal files. Understanding this source config provides valuable context for HAL management but should not be mutated outside the riocore workflow.

**Current Prototype**: User has built a Python prototype (`riocfg`) with similar functionality including velocity testing, trapvel integration, and PID tuning. This Zig implementation aims to provide a more performant, dependency-free alternative with better TUI UX.

**Deployment Environment**: Raspberry Pi 5 running Debian Trixie with LinuxCNC 2.9/2.10 installed. The app runs directly on the machine PC, accessing HAL APIs locally. Performance must be acceptable on Pi5 hardware.

**LinuxCNC API**: LinuxCNC provides C APIs for HAL manipulation (libhal) and general LinuxCNC control. The HAL API allows component discovery, pin/signal/param reading and writing, and component management. These are stable across LinuxCNC 2.9/2.10.

**Machine Setup Workflow**: When building a new CNC machine, the workflow is:
1. Determine feasible stepper speeds (velocity testing)
2. Characterize axis dynamics with trapvel profiling
3. Tune PID controllers based on known velocity/acceleration limits
4. Configure homing and other machine parameters

Each step requires real-time HAL manipulation and parameter persistence.

## Constraints

- **Platform**: Linux-only (Debian Trixie on Raspberry Pi 5) — HAL APIs are Linux-specific
- **LinuxCNC Version**: 2.9/2.10 — assumes stable HAL API across these versions
- **Language**: Zig — chosen for performance, single-binary deployment, FFI capabilities
- **TUI Library**: Vaxis — modern terminal UI library for Zig
- **Riocore Optional**: Must work with OR without riocore framework present
- **Performance**: Must run smoothly on Raspberry Pi 5 hardware
- **FFI Safety**: Zig wrapping layer must safely handle C pointers and memory from LinuxCNC APIs

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Zig over Python rewrite | Python prototype exists but Zig provides single binary, no deps, better performance for Pi5 deployment | — Pending |
| Vaxis for TUI | Modern Zig-native TUI library, actively maintained, good terminal compatibility | — Pending |
| Plugin architecture | Machine setup requires domain-specific workflows (velocity, trapvel, PID); plugins keep core clean and extensible | — Pending |
| Riocore view-only | Riocore config is source of truth; editing outside rio-setup risks config drift and regeneration issues | — Pending |
| Local-only operation | Runs on machine PC for direct HAL access; remote adds complexity and isn't needed for typical use case | — Pending |

---
*Last updated: 2025-01-28 after initialization*
