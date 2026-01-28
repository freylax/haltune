# Feature Research

**Domain:** LinuxCNC HAL Management Tools
**Researched:** 2025-01-28
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Pin browsing and inspection** | Users must view all HAL pins, their types, directions, and current values | LOW | Must show pin name, type (bit/s32/u32/float), direction (IN/OUT/I/O), current value, and connected signal |
| **Signal inspection** | Understanding signal flow is fundamental to HAL debugging | LOW | Must show signal name, type, value, and list of connected pins with directions |
| **Parameter viewing/editing** | Runtime tuning of parameters (PID gains, offsets) is core use case | LOW | Must distinguish between read-only and writable parameters; live editing required |
| **Component listing** | Users need to see what HAL components are loaded | LOW | Basic tree view or flat list of components and their instances |
| **Search/filter** | Complex HAL systems have hundreds of pins/signals | LOW | Pattern matching by name (glob support preferred), filtering by type |
| **Value refresh** | Real-time monitoring requires periodic updates | LOW-MED | Configurable refresh rate; must handle HAL mutex locking correctly |
| **net command equivalent** | Creating signals and linking pins is basic configuration | MED | Must support creating signals and linking multiple pins (halcmd `net` equivalent) |
| **setp/getp equivalents** | Setting parameter values is essential for tuning | LOW | Setting parameter values with validation |
| **Save configuration** | Users need to persist changes to HAL files | MED | Export current configuration in halcmd-compatible format |
| **Show all/filtered views** | Users expect to see everything or specific subsets | LOW | Commands like `show pin`, `show sig`, `show param`, `show all` |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **TUI interface (curses/terminal UI)** | No existing TUI HAL tools; works over SSH; fits LinuxCNC's terminal-centric workflow | HIGH | **Primary differentiator** - halcmd is CLI, halmeter/halshow/halscope are GUI. TUI fills gap |
| **Unified inspector** | Combines browsing, monitoring, and editing in one interface (halcmd + halmeter + halshow) | MED | Eliminates context switching between multiple tools |
| **Velocity testing** | Directly addresses "how fast can this stepper go?" question | MED-HIGH | Test velocity limits without editing G-code or using complex setups |
| **Trapvel integration** | Single-axis movements with ramped velocity profiles for testing | MED-HIGH | Valuable for commissioning and testing individual axes |
| **PID discovery and tuning interface** | Automatic PID component discovery vs. manual halcmd searching | MED-HIGH | Scans HAL for PID components, presents unified tuning interface per axis |
| **Riocore awareness** | Enhanced experience for Mesa/riocore users | LOW-MED | Detect riocore presence, show card-specific organization |
| **Live value graphs** | Mini-oscilloscope in TUI (lite halscope) | HIGH | Plotting values in terminal; ambitious but valuable |
| **Bookmark/watch list** | Save frequently monitored pins/signals | LOW-MED | Quick access to commonly viewed items |
| **History/undo** | Mistakes happen; ability to revert changes | MED | Track configuration changes, allow rollback |
| **Batch operations** | Apply same change to multiple items (e.g., set all enable pins) | LOW | Pattern-based bulk operations |
| **Diff mode** | Compare current HAL state to saved file | MED | Shows what changed since last save |
| **Smart filtering by component** | "Show all pins for pid.0" instead of manual pattern matching | LOW | Group pins/signals by their owning component |
| **Cross-references** | "What reads this signal?" "What writes this parameter?" | MED | Navigate relationships between HAL items |
| **Configuration validation** | Warn about unconnected pins, type mismatches, missing writers | MED-HIGH | Catch configuration errors before runtime |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Full HAL file editing** | Users want graphical HAL file editor | Becomes a full-blown IDE; scope creep; hard to maintain sync with running system | Use text editor for files; TUI for runtime manipulation only |
| **HAL component development** | "Write my own HAL components in the tool" | Different domain; should be separate IDE/editor | Use existing tools (comp/comp2, Python) for component dev |
| **Persistent background daemon** | "Keep monitoring after I exit" | Adds lifecycle management complexity; breaks "simple tool" model | User runs TUI when needed; separate monitoring tools (halscope) for long-term capture |
| **G-code integration** | "See how HAL affects motion" | Requires understanding motion controller, trajectory planning; out of scope | Use AXIS GUI for G-code visualization |
| **Real-time graphing in terminal** | "Halscope but in TUI" | Terminal refresh rates are too slow for meaningful oscilloscope; performance issues | Use actual halscope GUI for waveform analysis; limit TUI to value monitoring |
| **Auto-discovery of machine topology** | "Figure out my machine configuration automatically" | Heuristics will be wrong; makes assumptions that don't generalize | Let user explicitly define what's important (bookmarks, filters) |
| **Machine control (jog, MDI)** | "Control machine from TUI" | Duplicates existing GUIs; safety concerns; complex | Use existing LinuxCNC GUIs (AXIS, gmoccapy) for machine control |
| **Remote/network operation** | "Manage HAL over network" | Security implications; adds complexity | Use SSH to run haltune remotely (simple and secure) |
| **Configuration wizard** | "Step-by-step machine setup" | Every machine is different; wizard becomes outdated and opinionated | Provide good documentation and examples instead |

## Feature Dependencies

```
[TUI Framework]
    └──requires──> [Terminal UI Library]
                     └──requires──> [HAL Library Binding]

[HAL Inspector]
    └──requires──> [HAL Library Binding]
                    └──requires──> [LinuxCNC HAL Shared Library]

[Live Value Monitoring]
    └──requires──> [HAL Inspector]
    └──requires──> [Refresh Timer]

[Value Editing]
    └──requires──> [HAL Inspector]
    └──requires──> [HAL Lock/Unlock Handling]

[Velocity Tester]
    └──requires──> [HAL Inspector]
    └──requires──> [HAL Library Binding (setp commands)]
    └──enhances──> [HAL Inspector]

[PID Plugin]
    └──requires──> [HAL Inspector]
    └──requires──> [Component Discovery]
    └──requires──> [Value Editing]

[Live Value Graphs]
    └──requires──> [Live Value Monitoring]
    └──requires──> [TUI Canvas/Drawing Support]
    └──conflicts──> [Terminal Performance] (may be too slow)

[Configuration Save]
    └──requires──> [HAL Inspector]
    └──requires──> [halcmd-compatible Output Generation]
```

### Dependency Notes

- **TUI Framework requires HAL Library Binding**: Cannot build TUI without ability to query HAL; need language bindings (C, Python, or Zig FFI to libhal)
- **Velocity Tester enhances HAL Inspector**: Builds on value editing but adds specific motion testing logic
- **Live Value Graphs conflicts with Terminal Performance**: Drawing in terminal is slow; may need to be optional or limited
- **All runtime manipulation features require HAL Lock/Unlock Handling**: Must respect LinuxCNC's locking mechanism (lock/unlock commands)

## MVP Definition

### Launch With (v1)

Minimum viable product - what's needed to validate the concept.

- [ ] **HAL Inspector core** - Browse pins, signals, params, components with search/filter
  - *Why essential*: This is the foundation; without inspection, tool has no value
- [ ] **Live value monitoring with refresh** - See values update in real-time
  - *Why essential*: Runtime tuning is the primary use case; static inspection is insufficient
- [ ] **Value editing (setp)** - Change parameter values at runtime
  - *Why essential*: Tuning requires changing values, not just viewing them
- [ ] **net/linkps equivalent** - Create signals and link pins
  - *Why essential*: Basic configuration requires connecting components
- [ ] **TUI with tree/list views and navigation** - Usable terminal interface
  - *Why essential*: TUI is the primary differentiator over existing tools

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] **Velocity Tester** - Trigger for: Users need to test stepper speed limits
- [ ] **Save/load configuration** - Trigger for: Users want to persist runtime changes
- [ ] **PID discovery** - Trigger for: Users find manual PID component searching tedious
- [ ] **Bookmark/watch list** - Trigger for: Users repeatedly navigate to same items
- [ ] **Smart filtering by component** - Trigger for: Users need "show all X's pins"

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Live value graphs** - Defer: Terminal performance limitations; complex implementation
- [ ] **Trapvel Plugin** - Defer: Niche use case (single-axis testing); can be separate tool
- [ ] **History/undo** - Defer: Nice-to-have; not critical for initial use
- [ ] **Diff mode** - Defer: Advanced workflow; basic save/load suffices initially
- [ ] **Configuration validation** - Defer: Helpful but not blocking; users can detect issues manually
- [ ] **Riocore awareness** - Defer: Enhancement for specific hardware subset; generic HAL works for all

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| HAL Inspector (browse pins/sig/param) | HIGH | LOW-MED | **P1** |
| Live value monitoring | HIGH | LOW | **P1** |
| Value editing (setp) | HIGH | LOW | **P1** |
| TUI interface | HIGH | HIGH | **P1** |
| net/linkps (create signals) | HIGH | MED | **P1** |
| Search/filter by name | MED | LOW | **P1** |
| Save configuration | MED | MED | **P2** |
| Velocity Tester | MED | MED-HIGH | **P2** |
| PID discovery | MED | HIGH | **P2** |
| Bookmark/watch list | LOW-MED | LOW-MED | **P2** |
| Smart filtering by component | LOW-MED | LOW | **P2** |
| Live value graphs | MED | HIGH | **P3** |
| History/undo | LOW | MED | **P3** |
| Diff mode | LOW | MED | **P3** |
| Configuration validation | MED | HIGH | **P3** |
| Trapvel Plugin | LOW-MED | MED-HIGH | **P3** |
| Cross-references | LOW | MED | **P3** |
| Batch operations | LOW | MED | **P3** |

**Priority key:**
- **P1: Must have for launch** - Core HAL inspection and manipulation
- **P2: Should have, add when possible** - Important workflows but not blocking
- **P3: Nice to have, future consideration** - Enhancements that can wait

## Competitor Feature Analysis

| Feature | halcmd | halmeter | halshow | halscope | haltune (planned) |
|---------|--------|----------|---------|----------|------------------|
| **Browse pins/signals/params** | CLI (show cmd) | No | Yes (tree) | No | **Yes (TUI list/tree)** |
| **Live value monitoring** | Manual getp/gets | Yes (fast) | Yes (slow) | Yes (waveform) | **Yes (configurable rate)** |
| **Edit parameter values** | Yes (setp) | No | No | No | **Yes** |
| **Create/link signals** | Yes (net) | No | No | No | **Yes** |
| **Search/filter** | Yes (list cmd) | No | No | No | **Yes (glob patterns)** |
| **Save configuration** | Yes (save cmd) | No | No | No | **Yes** |
| **Waveform visualization** | No | No | No | Yes | No *(P3: basic graphs)* |
| **Component discovery** | Yes (show comp) | No | Yes | No | **Yes** |
| **TUI interface** | No (CLI) | No (GUI) | No (GUI) | No (GUI) | **Yes** |
| **Velocity testing** | No | No | No | No | **Yes** |
| **PID tuning focus** | No | No | No | Partial (view) | **Yes (discovery + edit)** |

**Key Insights:**
- **halcmd** is feature-complete for manipulation but has poor UX (CLI only, no persistent monitoring)
- **halmeter/halshow/halscope** are all GUI tools; no TUI exists in LinuxCNC ecosystem
- Each tool serves one purpose; users must switch between them for complete workflow
- **haltune's unique value**: Unified TUI that combines inspection, monitoring, editing, AND domain-specific tools (velocity, PID)

## Sources

- [LinuxCNC HAL Tools Documentation](https://linuxcnc.org/docs/html/hal/tools.html) - Official HAL tools reference (MEDIUM confidence)
- [HALCMD Man Page](https://linuxcnc.org/docs/html/man/man1/halcmd.1.html) - Complete halcmd command reference (HIGH confidence)
- [LinuxCNC HAL Tutorial](https://linuxcnc.org/docs/html/hal/tutorial.html) - HAL usage patterns (HIGH confidence)
- [Graphing a HAL Configuration (Forum)](https://forum.linuxcnc.org/24-hal-components/37821-graphing-a-hal-configuration) - Community discussion on visualization (LOW confidence)
- [hal-graph.py (GitHub)](https://github.com/koppi/mk/blob/master/linuxcnc/configs/koppi-cnc/hal-graph.py) - Python HAL visualization script (LOW confidence)
- [Tuning LinuxCNC/HAL PID Loops (Wiki)](http://wiki.linuxcnc.org/cgi-bin/wiki.pl?Tuning_LinuxCNC/HAL_PID_Loops) - PID tuning approaches (MEDIUM confidence)
- [PID Tuning Documentation](https://linuxcnc.org/docs/html/motion/pid-theory.html) - Official PID theory (HIGH confidence)
- [LinuxCNC User Introduction](https://linuxcnc.org/docs/2.7/html/user/user-intro.html) - Overview of available interfaces (MEDIUM confidence)

**Confidence notes:**
- **HIGH confidence**: Official LinuxCNC documentation and man pages
- **MEDIUM confidence**: Official docs with potential version drift, community wiki pages
- **LOW confidence**: Forum discussions, GitHub examples, single sources
- **Overall assessment**: Core HAL features (pins, signals, params, components) well-documented; TUI space completely unexplored (opportunity); velocity testing and PID tuning require inference from domain knowledge

---
*Feature research for: LinuxCNC HAL Management Tools*
*Researched: 2025-01-28*
