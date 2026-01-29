# haltune - LinuxCNC HAL Manager

## What This Is

A TUI-based LinuxCNC HAL manager written in Zig, providing real-time inspection and manipulation of HAL components (pins, signals, parameters, components). Includes workflow-specific plugins for machine setup tasks like velocity testing, trapvel profiling, and PID tuning. Works with standard LinuxCNC installations and has enhanced awareness for the riocore framework.

## Core Value

Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

## Requirements

### Validated

- ✓ **FFI Layer** — v0.4: Safe Zig bindings to LinuxCNC HAL C API with proper type conversions, struct alignment on ARM64, memory management, mutex locking, and LinuxCNC 2.9.7+ compatibility
- ✓ **State Management** — v0.4: Thread-safe central state store with RwLock, refresh timer at 100ms default, dynamic HAL change handling, and pubsub notifications
- ✓ **HAL Inspector Core** — v0.4: Browse all HAL components (pins, signals, parameters) with real-time updates, search/filter capabilities, and in-place editing
- ✓ **TUX Framework** — v0.4: Vaxis-based responsive TUI interface with two-panel layout (tree + data table), keyboard navigation, and Raspberry Pi 5 deployment
- ✓ **Config Persistence** — v0.4: Export current HAL configuration to halcmd-compatible format with 's' key binding (restore via halcmd -f for v1)

### Active

- [ ] **Signal Creation UI** — Create new signals and link pins via multi-step TUI wizard (FFI complete, dialog complete, visual rendering polish pending)
- [ ] **Riocore Awareness**: Detect and display riocore configuration context (view-only) when riocore framework is present
- [ ] **Velocity Tester Plugin**: Test stepper velocity limits in real-time to determine feasible operating ranges
- [ ] **Trapvel Plugin**: Single axis movements with ramped velocity profiles using trapvel.comp for axis characterization
- [ ] **PID Plugin**: Discover PID components in HAL and provide tuning interface with real-time parameter adjustment
- [ ] **Bookmarks**: Quick access to frequently monitored HAL items with persistent storage

### Out of Scope

- **Riocore config editing** — riocore config is view-only in v1; edits go through rio-setup (prevents config drift)
- **FPGA manipulation** — FPGA programming is outside scope; HAL integration focuses on software layer
- **Multi-machine support** — v1 assumes single LinuxCNC instance on local machine
- **Remote HAL access** — no network HAL manipulation; runs directly on machine PC
- **Motion program control** — not a G-code sender or motion controller; focuses on HAL/config layer
- **Real-time plotting** — no oscilloscope-style signal visualization in v1 (may come in v2)
- **Pin link tracking in export** — ULAPI signal pointer iteration too complex for v1; export shows empty pin lists (documented limitation)
- **Automated config restore** — Users must manually run halcmd -f filename.hal to restore saved configs (TUI restore deferred)

## Context

**Current State (v0.4):** Shipped with 5,009 LOC Zig. FFI layer complete with pin/signal/parameter read/write operations. State management with thread-safe RwLock cache and 100ms refresh. TUI with two-panel layout (tree + data table), search/filter, in-place editing. Signal creation dialog and config export complete with known v1 limitations (pin link tracking, save dialog visual polish).

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
| Zig over Python rewrite | Python prototype exists but Zig provides single binary, no deps, better performance for Pi5 deployment | ✓ Good - FFI layer complete, single binary deployment achieved |
| Vaxis for TUI | Modern Zig-native TUI library, actively maintained, good terminal compatibility | ✓ Good - Two-panel layout working, responsive on Pi5 |
| Plugin architecture | Machine setup requires domain-specific workflows (velocity, trapvel, PID); plugins keep core clean and extensible | — Pending - Phase 5 will implement |
| Riocore view-only | Riocore config is source of truth; editing outside rio-setup risks config drift and regeneration issues | — Pending - Not yet implemented |
| Local-only operation | Runs on machine PC for direct HAL access; remote adds complexity and isn't needed for typical use case | ✓ Good - All FFI calls local, no network complexity |
| halSignalNew no mutex | C function handles locking internally, wrapper doesn't acquire mutex | ✓ Good - Documented in Thread safety, prevents double-locking |
| StringHashMap for selections | Simpler than tracking full state, only need O(1) membership test | ✓ Good - Dialog selection pattern working well |
| ArrayList(u8) for input | Proper UTF-8 backspace handling via pop() method | ✓ Good - Both search and save filename using this pattern |
| Defer pin link tracking | ULAPI signal pointer iteration too complex for v1, documented in TODO | ⚠️ Revisit - Export shows empty pin lists, v2 enhancement |
| Stub dialog draw | Focus on functionality first, visual rendering can be enhanced later | ⚠️ Revisit - Dialogs work but need polish (Phase 5 or 6) |

---
*Last updated: 2026-01-29 after v0.4 milestone*
