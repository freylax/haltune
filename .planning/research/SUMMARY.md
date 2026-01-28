# Project Research Summary

**Project:** haltune — LinuxCNC HAL Management Tool
**Domain:** CNC control system HAL management and inspection tool
**Researched:** 2026-01-28
**Confidence:** HIGH

## Executive Summary

Haltune is a terminal user interface (TUI) tool for managing LinuxCNC HAL (Hardware Abstraction Layer) systems, filling a critical gap in the LinuxCNC ecosystem. Existing tools are either command-line (halcmd) or GUI-based (halmeter, halshow, halscope), with no TUI option for users who need SSH-friendly, keyboard-driven interaction. Research indicates this is a greenfield opportunity — no TUI HAL management tools exist in the LinuxCNC ecosystem.

The recommended approach is building on Zig 0.15.2 with the Vaxis TUI framework, providing safe FFI bindings to LinuxCNC's C API. Zig's modern C interop and memory safety make it well-suited for this domain, though careful attention must be paid to FFI safety, struct alignment (especially ARM64 for Raspberry Pi 5), and real-time thread safety. The architecture follows a clean separation: FFI layer → HAL wrapper → state manager → TUI views, with a plugin system for domain-specific workflows like PID tuning.

Key risks center on FFI safety and real-time constraints. LinuxCNC HAL operates with real-time threads that cannot tolerate blocking operations; improper FFI calls can cause machine faults or stepper errors. Memory management across the C/Zig boundary must be rigorously controlled to prevent heap corruption. Raspberry Pi 5 deployment adds performance constraints — TUI refresh rates and HAL polling must be optimized to avoid starving real-time threads. Despite these challenges, the research shows a clear path forward with well-documented LinuxCNC APIs and mature Zig tooling.

## Key Findings

### Recommended Stack

Zig 0.15.2 (stable) with Vaxis TUI framework provides the foundation. Zig's modern approach to C interop via `@cImport` and explicit memory management aligns well with LinuxCNC's C API. The FFI layer must use `extern struct` for all C structs to ensure matching layout, especially critical for ARM64 (Raspberry Pi 5). Vaxis offers both low-level TUI primitives and a high-level vxfw widget framework; research recommends starting with vxfw for rapid development while retaining the option to drop down when needed.

**Core technologies:**
- **Zig 0.15.2** — Core language; latest stable release, proven production readiness, excellent C FFI support
- **Vaxis (libvaxis)** — TUI framework; modern, actively maintained, uses terminal queries (not terminfo), provides both low-level and high-level APIs
- **LinuxCNC HAL 2.9.7+** — Target API; stable with documented C library, halcmd for reference implementation
- **zig-clap or yazap** — CLI parsing; choose based on feature needs (yazap for comprehensive CLI, zig-clap for simplicity)

### Expected Features

HAL management tools have well-established table stakes features. Users expect pin/signal/parameter inspection with search and filtering, live value monitoring, and runtime parameter editing (setp). The ability to create signals and link pins (halcmd `net` command equivalent) is fundamental to configuration workflows. What differentiates haltune is the TUI interface — no existing tool provides terminal-based HAL inspection combined with live editing and domain-specific plugins.

**Must have (table stakes):**
- Pin/signal/param browser — users expect to navigate HAL hierarchy, view types and directions
- Live value monitoring — runtime tuning requires seeing values update in real-time
- Value editing (setp) — tuning requires changing values, not just viewing
- net/linkps equivalents — basic configuration requires connecting pins to signals
- Search/filter — complex HAL systems have hundreds of pins, navigation is impossible without filtering

**Should have (competitive):**
- TUI interface — primary differentiator; works over SSH, fits LinuxCNC workflow
- Unified inspector — combines browsing + monitoring + editing in one interface
- Velocity testing — addresses "how fast can this stepper go?" question directly
- PID discovery — scans HAL for PID components, presents unified tuning interface

**Defer (v2+):**
- Live value graphs — terminal refresh rates too slow for meaningful oscilloscope
- History/undo — nice-to-have but not blocking for initial use
- Configuration validation — helpful but users can detect issues manually
- Trapvel plugin — niche use case, can be separate tool

### Architecture Approach

The research strongly favors a layered architecture with strict boundaries. The FFI layer at the bottom provides safe wrappers for all LinuxCNC C API calls, using Zig's error handling and option types to prevent undefined behavior. Above this, a HAL wrapper offers idiomatic Zig operations (pin.read(), signal.write()) that abstract away C complexity. A centralized state manager with pub/sub caching eliminates race conditions when multiple TUI components access HAL data. The TUI layer (Vaxis) only talks to the state manager, never directly to HAL — this separation enables testing and prevents UI code from blocking real-time threads.

**Major components:**
1. **FFI Layer** — Safe C interop, memory ownership rules, struct alignment, version compatibility
2. **HAL Wrapper** — Type-safe pin/signal/param operations, error handling, caching
3. **State Manager** — Centralized cache with mutex protection, pub/sub for value changes, subscription filtering
4. **TUI Framework (Vaxis)** — Terminal rendering, event handling, widget composition, layout management
5. **Plugin System** — Domain-specific workflows (PID tuning, velocity testing) with stable API boundary

### Critical Pitfalls

Real-time safety is the most critical concern. LinuxCNC uses real-time threads with microsecond deadlines; blocking calls (I/O, allocation, locks) from these threads cause machine faults. The FFI layer must clearly document which functions run in real-time context and prevent blocking operations at the boundary. Memory management across the FFI boundary is equally critical — Zig and C allocators may use different heaps, so ownership must be explicit and C data must be cloned into Zig-owned memory before crossing boundaries.

1. **Blocking calls in real-time context** — identify real-time functions, pre-allocate all memory, use spinlocks sparingly, document real-time boundaries in FFI layer
2. **Memory management across FFI boundary** — explicit ownership rules, prefer Zig allocation, clone C data before returning, test error paths for cleanup
3. **Struct alignment mismatches** — use `extern struct` for all FFI structs, verify with compile-time `@sizeOf` assertions, test ARM64 (Pi 5) early
4. **Race conditions on HAL state** — acquire HAL mutex properly, use snapshot pattern (copy under lock, release lock, process copy), subscribe to component load/unload events
5. **Real-time thread starvation on Pi 5** — batch HAL reads, throttle refresh to 10-30fps, background thread for heavy operations, profile on actual Pi 5 hardware

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: FFI Foundation
**Rationale:** The FFI layer is the foundation everything else builds on. Getting struct alignment, memory ownership, and error handling wrong requires rewriting all subsequent code. Research shows FFI safety issues (Pitfalls 1, 2, 3, 6, 9) are most critical and must be addressed first.
**Delivers:** Safe LinuxCNC HAL bindings with comprehensive error handling, type-safe wrappers, version compatibility (2.9/2.10), and ARM64-tested struct layout
**Addresses:** All table stakes HAL operations (read pins/signals/params, list components)
**Avoids:** Pitfall 2 (memory corruption), Pitfall 3 (struct mismatches), Pitfall 6 (version incompatibility), Pitfall 9 (type coercion)

### Phase 2: State Management
**Rationale:** Before building UI, need a thread-safe caching layer that prevents race conditions when multiple components access HAL. The state manager with pub/sub enables clean separation between HAL and UI.
**Delivers:** Centralized state store with mutex-protected caching, subscription-based change notifications, snapshot pattern for safe reads, component lifecycle tracking
**Uses:** HAL wrapper from Phase 1, Zig stdlib threading primitives
**Implements:** Architecture Pattern 2 (Centralized State Store with Pub/Sub)
**Avoids:** Pitfall 4 (race conditions on HAL state)

### Phase 3: TUI Core
**Rationale:** With solid foundation, build the primary differentiator — the TUI interface. Vaxis integration provides terminal rendering and event handling. Browser view enables pin/signal/param navigation.
**Delivers:** Vaxis TUI application with browser view (tree/list navigation), search/filter, live value display, basic parameter editing
**Uses:** State manager for all HAL access, Vaxis for rendering, vxfw for widgets
**Implements:** Table stakes features (browse, monitor, edit, search)
**Avoids:** Pitfall 5 (real-time starvation), Pitfall 7 (TUI input lag), Pitfall 10 (terminal assumptions)

### Phase 4: Configuration & Editing
**Rationale:** Users need to manipulate HAL, not just view it. This phase adds signal creation, pin linking, and configuration persistence.
**Delivers:** net/linkps equivalents (create signals, link pins), save/load configuration, watch list/bookmarks, advanced filtering by component
**Uses:** State manager mutations, Config loader (INI/HAL parsing)
**Implements:** Remaining table stakes features, P2 features (save config, bookmarks, smart filtering)
**Avoids:** Pitfall 8 (riocore config drift)

### Phase 5: Plugin System
**Rationale:** Domain-specific workflows (PID tuning, velocity testing) don't belong in core. Plugin architecture enables extensibility without complicating main codebase.
**Delivers:** Plugin manager with compile-time plugin loading, PID tuner plugin (discovers PID components, unified tuning interface), plugin API (state access, HAL operations, subscriptions)
**Uses:** State manager plugin API, Vaxis widget composition
**Implements:** Architecture Pattern 3 (View-Plugin Architecture), P2 differentiators
**Avoids:** Pitfall 4 (tight plugin-core coupling)

### Phase 6: Polish & Optimization
**Rationale:** Performance tuning and UX refinement come after functionality is complete. Raspberry Pi 5 optimization is critical for real deployment.
**Delivers:** Pi 5 performance optimization (refresh throttling, lazy evaluation, incremental rendering), terminal capability detection, riocore integration (detection, warnings, export), comprehensive error context
**Uses:** Profiling tools, Pi 5 hardware testing, multiple terminal emulators
**Implements:** P3 features (live graphs, history/undo), performance optimizations, UX polish
**Avoids:** Pitfall 5 (starvation), Pitfall 7 (input lag), Pitfall 11 (poor error context)

### Phase Ordering Rationale

The order prioritizes safety-critical foundations over user-facing features. FFI layer comes first because FFI bugs corrupt everything and are expensive to retrofit. State management before UI prevents race conditions that would otherwise emerge once TUI adds concurrent access. TUI core before plugins ensures stable platform for plugin development. Performance tuning last because premature optimization wastes time — profile on real hardware first.

This grouping aligns with ARCHITECTURE.md's build order recommendations and PITFALLS.md's phase mapping. Each phase delivers testable functionality while addressing specific pitfalls from research.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** FFI layer requires precise LinuxCNC 2.9 vs 2.10 API differences research; conditional compilation strategy needs detailed planning
- **Phase 3:** Vaxis integration patterns research; TUI state management with real-time updates may need architecture exploration
- **Phase 5:** Plugin architecture research; compile-time vs process-based plugins trade-off needs decision

Phases with standard patterns (skip research-phase):
- **Phase 2:** State management with pub/sub is well-established pattern; Zig threading primitives are standard
- **Phase 4:** Configuration parsing (INI/HAL files) is standard file parsing; halcmd provides reference for export format
- **Phase 6:** Performance optimization follows standard profiling practices; terminal capability detection is solved problem

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Zig 0.15.2 and Vaxis are stable, well-documented. LinuxCNC HAL API officially documented. Clear version pinning strategy. |
| Features | HIGH | Table stakes features well-established from halcmd/halshow documentation. Differentiators validated against existing tool gaps. |
| Architecture | HIGH | Layered architecture with FFI→HAL→State→TUI is standard pattern. Component boundaries clearly defined. |
| Pitfalls | HIGH | Real-time safety, FFI safety, and memory management risks well-documented in LinuxCNC and Zig communities. ARM64 testing requirements explicit. |

**Overall confidence:** HIGH

### Gaps to Address

- **Vaxis integration patterns:** Research provided Vaxis documentation but few real-world integration examples. May need exploration during Phase 3 planning for state management patterns specific to Vaxis's event loop.
- **Plugin loading strategy:** Research shows dynamic plugin loading in Zig is immature (community pain point). Decision required: compile-time plugins (simpler, recommended) vs process-based plugins (more flexible, complex). Defer to Phase 5 planning.
- **Pi 5 performance baseline:** Research identified Pi 5 constraints but no specific benchmarks for TUI refresh rates or HAL polling overhead. Must profile during Phase 6 to establish acceptable performance targets.

## Sources

### Primary (HIGH confidence)
- [LinuxCNC Developer Manual V2.9.7](http://linuxcnc.org/docs/2.9/pdf/LinuxCNC_Developer_nb.pdf) — HAL C API, shared memory IPC, real-time architecture (Oct 22, 2025)
- [HALCMD Man Page](https://linuxcnc.org/docs/html/man/man1/halcmd.1.html) — Complete command reference, all table stakes operations
- [HAL Tools Documentation](https://linuxcnc.org/docs/html/hal/tools.html) — Reference for halcmd, halmeter, halshow, halscope features (Dec 15, 2025)
- [LinuxCNC HAL Component Documentation](https://linuxcnc.org/docs/stable/html/hal/comp.html) — Real-time constraints, blocking call restrictions (Dec 15, 2025)
- [GitHub: rockorager/libvaxis](https://github.com/rockorager/libvaxis) — Vaxis TUI framework, API reference, examples (actively maintained 2025)
- [Zig 0.15.2 Documentation](https://ziglang.org/documentation/0.15.2/) — Language features, FFI patterns, @cImport usage

### Secondary (MEDIUM confidence)
- [HAL Tutorial](https://linuxcnc.org/docs/html/hal/tutorial.html) — HAL usage patterns, pin/signal/param concepts
- [Zig FFI Safety Patterns](https://marsmatics.com/how-zig-lets-you-gradually-migrate-or-mix-c-code-safely/) — June 2025, C interop best practices
- [Architecting for Control with CLIs and TUIs](https://www.golodiuk.com/news/ui-in-architecture-01-cli-tui/) — TUI architecture patterns
- [GitHub: multigcs/riocore](https://github.com/multigcs/riocore) — Riocore framework detection patterns
- [LinuxCNC on Raspberry Pi 5 Forum Thread](https://forum.linuxcnc.org/9-installing-linuxcnc/50203-linuxcnc-on-raspberry-pi-5) — Real-world Pi 5 performance constraints

### Tertiary (LOW confidence)
- [Graphing a HAL Configuration (Forum)](https://forum.linuxcnc.org/24-hal-components/37821-graphing-a-hal-configuration) — Community visualization discussions
- [PID Tuning Documentation](https://linuxcnc.org/docs/html/motion/pid-theory.html) — PID tuning domain knowledge
- [Zig Plugin System Discussions](https://ziggit.dev/t/creating-cross-platform-plugin-system/8099) — Community pain points around dynamic loading
- [Riocore Setup from Scratch (Forum)](https://forum.linuxcnc.org/9-installing-linuxcnc/53710-riocore-setup-from-scratch-for-dummies) — September 2024, riocore workflow

---
*Research completed: 2026-01-28*
*Ready for roadmap: yes*
