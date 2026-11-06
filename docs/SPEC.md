# MtelLink — Product & Technical Spec

**Status:** Draft v0.1 · **Date:** 2026-11-06 · **Owner:** TBD

MtelLink diffs and merges Simulink models (`.slx`) inside Git and CI workflows. It works without a MATLAB install and gives results that both machines and the pull-request page can use.

---

## 1. Problem

Simulink models are stored as zipped XML (`.slx`). Git treats them as binary, so:

- `git diff` shows nothing useful, and PR reviewers can't see what changed.
- Any two branches that both edit the same model produce a file-level conflict, even when they changed different subsystems.
- Today's tools fall into two groups. Desktop GUIs launched as `difftool`/`mergetool` (e.g. EnSoft SimDiff) are built for one engineer at a workstation. MathWorks' own Comparison Tool, Three-Way Merge and `mlAutoMerge` need MATLAB, which means a MATLAB license on every CI runner that diffs or merges.

## 2. Goals and non-goals

### Goals (v1)
1. **Structural diff** of two `.slx` files: blocks, connections, parameters and subsystem hierarchy, with layout-only changes suppressed by default.
2. **Three-way merge** that resolves non-overlapping edits automatically and always writes either a valid `.slx` or a clear conflict report. It must never write a corrupt model.
3. **No MATLAB needed:** a single static binary for Windows, Linux and macOS.
4. **Built into Git:** `git diff` shows readable model changes, and `git merge` resolves model conflicts automatically where it can.
5. **Built for CI and PRs:** a GitHub Action posts a diff summary and HTML report on each PR, and machine-readable output supports policy checks.

### Non-goals (v1)
- Simulating, compiling or editing models (beyond what merging requires).
- `.mdl` text format, data dictionaries (`.sldd`), System Composer and requirements links. These are v2 candidates.
- Fine-grained Stateflow merge. Charts are diffed in detail but merged as a single unit in v1.
- A full desktop GUI. v1 provides a browser-based viewer, and interactive conflict resolution comes in M5.

## 3. Users and core jobs

| User | Job | Surface |
|---|---|---|
| Controls/model engineer | "What did I (or my colleague) change in this model?" | CLI, `git diff`, HTML report |
| Engineer merging branches | "Merge `feature` into `main` without hand-redoing edits in Simulink" | Git merge driver, `mtel merge` |
| PR reviewer | "Review model changes without checking out the branch or opening MATLAB" | PR comment + hosted report |
| Tooling / DevOps owner | "Block PRs that touch safety-critical subsystems without sign-off" | `mtel check` + policy file in CI |

## 4. Product surfaces

### 4.1 CLI (`mtel`)
```
mtel diff  <old.slx> <new.slx> [--format text|json|html] [--include-cosmetic] [-o out]
mtel merge <base.slx> <ours.slx> <theirs.slx> -o <out.slx> [--report conflicts.json]
mtel show  <model.slx> [--format text|json]        # dump normalized model tree
mtel check <old.slx> <new.slx> --policy policy.yml # exit 1 on policy violation
mtel validate <model.slx>                           # structural integrity check
mtel textconv <model.slx>                           # stable text form for git diff
```
Exit codes: `0` success/no diff, `1` differences/conflicts/policy violation, `2` usage or parse error.

### 4.2 Git integration
`mtel install-git [--global]` writes the following:
```gitattributes
# .gitattributes
*.slx  diff=mtel merge=mtel
```
```ini
# .git/config
[diff "mtel"]
    textconv = mtel textconv
    binary = true
[merge "mtel"]
    name = MtelLink Simulink merge
    driver = mtel merge %O %A %B -o %A --report %A.mtel-conflicts.json
```
- **textconv** makes `git diff`, `git log -p` and `git show` print a stable, line-oriented representation of the model (one block or connection per line, sorted by hierarchy path). Plain text diff on that form is already useful.
- **merge driver:** on success it writes the merged model to `%A` and exits 0. On conflict it leaves `%A` as "ours", writes a conflict report next to it and exits 1, so Git marks the file as conflicted. Conflict markers can't go inside a binary file, so the report replaces them.
- `difftool`/`mergetool` entries are also documented, pointing at `mtel diff --format html --open`.

### 4.3 GitHub Action (`mtellink/action`)
For each PR it:
1. Finds changed `*.slx` files and fetches the base and head blobs.
2. Runs `mtel diff --format json,html` for each file.
3. Posts or updates one PR comment with per-model summary counts and the top changes, and uploads the HTML reports as workflow artifacts.
4. Optionally runs `mtel check --policy .mtel/policy.yml` and fails the job on violations.

GitLab CI and Bitbucket Pipelines templates follow the same steps; they're open question Q4.

### 4.4 Web viewer (M4)
A static, self-contained HTML report that renders the subsystem diagrams as SVG with diff overlays (added = green, deleted = red, modified = amber, moved = blue). It supports click-through into subsystems and side-by-side parameter tables. The same renderer later powers a GitHub App that shows the viewer inside the PR.

## 5. Technical design

### 5.1 Language and packaging
**Rust** core library (`mtel-core`) plus a CLI binary.
- Ships as one static binary per platform, which suits Git drivers on locked-down Windows engineering machines.
- Compiles to **WASM**, so the browser viewer and GitHub App reuse the same parser and diff engine.
- Gives predictable performance on large models (10k+ blocks).

Workspace layout:
```
crates/
  mtel-slx/      # OPC zip + XML read/write, version handling
  mtel-model/    # normalized in-memory model graph
  mtel-match/    # element correspondence across versions
  mtel-diff/     # diff computation, classification, serializers
  mtel-merge/    # three-way merge, conflict model, SID renumbering
  mtel-validate/ # structural integrity rules
  mtel-render/   # SVG layout rendering
  mtel-cli/
web/             # viewer (TS) consuming mtel-render via WASM
action/          # GitHub Action wrapper
corpus/          # test models + synthetic mutation tooling
```

### 5.2 The `.slx` format (working assumptions — verify in M0)
- An `.slx` file is an OPC (Open Packaging Conventions) zip containing `[Content_Types].xml`, `_rels/`, `metadata/` and a `simulink/` folder.
- The model content is XML. Recent releases split it into per-subsystem files (`simulink/systems/system_root.xml`, `system_<N>.xml`), while older releases use a single `simulink/blockdiagram.xml`. Configuration sets, graphical interface and Stateflow content (`simulink/stateflow.xml`) live in separate parts.
- `<Block BlockType=… Name=… SID=…>` elements hold `<P Name=…>` parameters. `<Line>` elements reference endpoints as `SID#out:N` / `SID#in:N`, possibly with `<Branch>` children.
- **SIDs** are unique within a model and are allocated from a model-level high-water mark. Two branches can therefore assign **the same SID to different new blocks**, and the merge must handle that (§5.6).

**M0 deliverable:** a format notes document listing the parts, elements and attributes observed per MATLAB release across the corpus, with a supported-release matrix. Target R2019b and later; see Q3.

**Round-trip rule:** the writer must keep every part and attribute it doesn't understand. Merges change only the elements involved and copy everything else byte-for-byte where possible.

### 5.3 Normalized model (`mtel-model`)
```
Model { name, version, config_sets, root: System, unknown_parts }
System { path, blocks: Map<Sid, Block>, connections: Set<Conn>, annotations }
Block  { sid, name, block_type, params: Map<String, Value>, ports, child: Option<System>,
         library_link: Option<LibRef>, layout: Layout }
Conn   { src: (Sid, PortKind, idx), dst: (Sid, PortKind, idx) }   // branch trees flattened
```
- Lines are **flattened into point-to-point connections**. Branch geometry belongs in `layout` and counts as cosmetic.
- Parameters are split into **semantic** (e.g. `Gain`, `SampleTime`, `OutDataTypeStr`) and **cosmetic** (`Position`, `ZOrder`, line points, fonts, colors) using a per-block-type registry. Unknown parameters default to semantic.

### 5.4 Matching (`mtel-match`): the hard part
Matching runs per system, top-down:
1. **SID match:** pair blocks with the same SID and same `BlockType`. If a block keeps its SID but its parent changed, it was **moved**. If the SID is the same but the name changed, it was **renamed**.
2. **Fallback match** for blocks still unmatched (copy/paste, delete-and-recreate, SID collisions): build candidate pairs with the same `BlockType` in corresponding systems. Score each pair as a weighted sum of name equality or similarity, semantic-parameter overlap, connectivity similarity (matched neighbors on the same ports) and position proximity. Then solve with the Hungarian algorithm, applying a minimum score threshold.
3. **Iterate:** new matches improve the connectivity scores, so step 2 repeats until no new matches appear (bounded number of rounds).
4. **Connections** match by their endpoints once the blocks are paired.

Match quality is measured against labeled pairs from the mutation corpus (§7).

### 5.5 Diff (`mtel-diff`)
Change kinds: `BlockAdded`, `BlockDeleted`, `BlockMoved`, `BlockRenamed`, `ParamChanged{name, old, new}`, `ConnAdded`, `ConnDeleted`, `LibraryLinkChanged`, `ConfigSetChanged`, `StateflowChartChanged{details}`, `CosmeticChanged` (hidden by default).

The JSON output schema is versioned (`"schema": "mtel.diff/1"`) and every change carries a stable hierarchy path such as `Controller/PID/Kp`. JSON is the contract for the Action, policy checks and third-party tools, so it gets a published schema and changes only with a schema version bump.

### 5.6 Three-way merge (`mtel-merge`)
1. Match base↔ours and base↔theirs, which yields two change sets against the base.
2. Apply each change from either side when it doesn't touch the same element and parameter as the other side. Identical changes on both sides merge cleanly.
3. **Conflicts** (reported, never silently resolved):
   - The same parameter changed to different values.
   - One side modified or moved an element that the other side deleted.
   - Both sides added a block with the same name in the same system (Simulink requires unique names).
   - **Port driver conflict:** a merged result would give one input port more than one source.
   - Both sides changed the same Stateflow chart (whole-chart merge in v1).
   - Both sides changed the same config set parameter differently.
4. **Automatic fixes** (applied and logged):
   - **SID collision:** renumber the colliding new blocks on the "theirs" side above `max(ours, theirs)` high-water mark, update every reference to them, and update the model's high-water mark.
   - Layout: take ours unless only theirs changed. Overlapping positions are accepted, since the model still loads.
5. **Validate before writing** (§5.7). If validation fails, the merge is treated as a conflict and no output is written.

The conflict report (`mtel.conflicts/1` JSON plus a human-readable summary) lists each conflict with its path, base/ours/theirs values and a suggested resolution. M5 adds `mtel resolve` (interactive, CLI and web) to apply choices and re-validate.

### 5.7 Validation (`mtel-validate`)
Validation runs after every merge and on demand. It checks that:
- The XML is well-formed and the OPC parts and content types are consistent.
- SIDs are unique and below the high-water mark.
- Block names are unique within each system, and every connection endpoint exists and is a valid port.
- No input port has more than one driver.
- Subsystem port blocks match the parent block's port count.

**Optional MATLAB check:** in environments that have MATLAB, `mtel validate --matlab` runs `load_system` and an update-diagram on the result. This is used in our own CI on the corpus and is opt-in for customers.

### 5.8 Rendering (`mtel-render`)
The renderer draws an SVG for each system from block `Position` and line points, using generic block shapes with the block type label (no MathWorks icon assets), and lays the diff overlay on top. Pixel-perfect matching with Simulink is not a goal.

### 5.9 Performance targets
- `diff` of a 10k-block model: under 2 s and under 500 MB RAM.
- `textconv` under 1 s for typical models, because Git calls it for every revision shown.

## 6. Policy checks (`.mtel/policy.yml`)
```yaml
rules:
  - name: safety-subsystem-review
    when: { path: "Plant/Safety/**", change: any }
    require: { label: "safety-approved" }   # evaluated by the Action against PR labels
  - name: no-config-drift
    when: { change: ConfigSetChanged }
    action: fail
  - name: no-cosmetic-noise
    when: { only: CosmeticChanged }
    action: warn
```

## 7. Testing strategy
1. **Corpus:** public, permissively licensed Simulink models (e.g. open-source projects on GitHub and published research corpora such as SLNET), checked for license terms before inclusion, and spread across MATLAB releases.
2. **Round-trip tests:** read and write every corpus model, then require semantic equivalence and that `--matlab` validation passes.
3. **Mutation-based diff tests:** apply random known edits (add, delete, move, rename, change parameter, rewire) to a model, then check that `diff` reports exactly that edit set. These tests also produce labeled data for matching accuracy.
4. **Mutation-based merge tests:** apply disjoint edit sets A and B to a base model. `merge(base, base+A, base+B)` must equal `base+A+B` and pass validation. Overlapping edit sets must produce exactly the expected conflicts.
5. **Fuzzing** of the XML/OPC reader to catch crashes on malformed input.
6. **CI matrix:** Windows, Linux and macOS for the binary, plus a nightly MATLAB job running `--matlab` validation on the corpus.

**Release gate:** zero merged outputs that fail to load in MATLAB across the corpus and mutation suite.

## 8. Milestones
| # | Milestone | Exit criteria |
|---|---|---|
| M0 | Corpus + format notes + `mtel-slx` read/write | Lossless round-trip on 100% of corpus |
| M1 | Model graph, matching, two-way `diff` (text/json), `show`, `textconv` | ≥ 98% exact edit recovery on mutation suite |
| M2 | Git install, HTML report, GitHub Action, `check` | Action running on a pilot repo |
| M3 | Three-way `merge` + merge driver + `validate` | Release gate in §7 met |
| M4 | SVG renderer + interactive web viewer | Reviewers can review a PR without MATLAB |
| M5 | `mtel resolve`, GitHub App, Stateflow fine-grained merge, `.mdl` | Scoped after M3 |

## 9. Success metrics
- Pilot users run merges with **zero** corrupted models.
- At least 70% of model conflicts on pilot repos are resolved automatically (baseline: 0% with plain Git).
- Median PR review of a model change happens without anyone opening MATLAB.
- Matching accuracy of at least 98% on the labeled mutation set.

## 10. Risks
| Risk | Mitigation |
|---|---|
| The undocumented `.slx` format changes between MATLAB releases | Per-release format notes, lossless pass-through of unknown content, nightly MATLAB validation, supported-release matrix |
| A merge writes a model that loads but behaves differently | Conservative conflict rules (report rather than guess), validation, mutation merge tests, a clear "review merged models" message in docs |
| Matching errors produce confusing diffs | Labeled accuracy benchmark, explainable match scores in `--debug` output |
| Stateflow complexity | Whole-chart merge in v1, fine-grained merge deferred to M5 |
| Legal/IP | Interoperability-focused implementation built only from file inspection; no MathWorks or EnSoft code, icons or UI copied; nominative-only use of "Simulink"; counsel review of the MATLAB license before using MATLAB in our CI |

## 11. Competitive positioning
| | MtelLink | EnSoft SimDiff | MathWorks Comparison / Three-Way Merge / `mlAutoMerge` |
|---|---|---|---|
| Needs MATLAB | No | No (desktop tool) | Yes |
| Readable `git diff` | Yes (textconv) | No | No |
| Headless merge driver | Yes | GUI mergetool | `mlAutoMerge` (needs MATLAB) |
| PR comment / report | Yes (Action) | Not found | Documented CI report recipe |
| Machine-readable output + policy | Yes | Not found | Partial |

## 12. Open questions
- **Q1** Licensing model: open-core (free CLI and Action, paid App and resolve UI) or fully commercial?
- **Q2** Is "no MATLAB required" a hard requirement for every feature, or can some (e.g. rendering fidelity) optionally use MATLAB?
- **Q3** Minimum supported MATLAB release? The proposed R2019b+ should be confirmed against pilot users.
- **Q4** GitHub only for v1, or GitLab and Bitbucket too?
- **Q5** Does a Windows desktop GUI matter to buyers, or is the browser viewer enough?
- **Q6** Pilot partners and their model sizes, MATLAB versions and toolboxes in use.
