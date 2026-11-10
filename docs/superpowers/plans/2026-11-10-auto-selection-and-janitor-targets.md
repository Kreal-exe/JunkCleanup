# Auto selection, one cleanable number, mac-janitor targets — Implementation Plan

> **For agentic workers:** executed natively (superpowers:executing-plans) in one session; steps use `- [ ]`.

**Goal:** JunkCleanup on macOS picks what to clean by itself (safe / safe + moderate / by hand), shows one
"can be cleaned" number everywhere, and finds and removes what the `mac-janitor` watcher removes: abandoned Chrome
code-sign clones, an unused Cowork VM, idle Claude/program temp folders, clang's module cache, Hermes caches,
hyperframes' downloads, and stuck processes.

**Architecture:** everything cleanable becomes a cleaner target (`CCTarget`), so the Targets scan is the single
source of the number; the Disk page only maps and points at targets. New target features: `idleDays`,
`deletesWholeRoots`, `sharesBlocks` (APFS private size), `beforeClean`. Process checks live in a new
Foundation-only `CCProcesses` module, shown as a card on Overview.

**Tech Stack:** Objective-C, AppKit, Foundation; `build.sh`, `build.sh --test` (MacApp/Tests/CoreTests.m).

**Spec:** the task brief from the session that started this one, plus the user's request (2026-11-10): "the program
picks itself what can go: caches, then safe caches, not-safe ones, models"; a "safe only" switch; the 2.16 GB the
Disk page promised must be what Overview shows and cleans.

## Global Constraints

- Never launch or kill the user's Chrome; Hermes' Chrome only through `~/.claude/skills/hermes-browser/scripts/hb-stop`.
- `lsof` only per pid with `-b -n -w` (it hangs on the network share otherwise); no searches of `/`.
- A clone belongs to a running Chrome when its birthtime is within ±180 s of a running main Chrome process
  (`…/Contents/MacOS/Google Chrome`, any profile); only the others are offered.
- Cowork VM is offered only when no `scheduled-tasks.json` has a non-empty `scheduledTasks` and nothing in the session
  folders (except `rpm`, `scheduled-tasks.json`, the `skills-plugin` account) changed for 24 h; before removal stop
  only the `com.apple.Virtualization.VirtualMachine` process that has the bundle open.
- Thresholds: Claude session temp 3 days idle; `/private/tmp/{tmp*,pymp-*,jobs-test-*}` 1 day; clang ModuleCache
  7 days; orphan shell > 10 min, > 20 % of a core on average, no children, parent launchd; disk-wide search > 5 min,
  started by Claude, over `/`, `/Volumes…`, `/System/Volumes/Data`, `/Users`; Hermes renderer > 2.5 GB
  (or > 100 % CPU with `hb` idle > 15 min).
- Every new string in all 19 languages (tests check it).
- Already present, not duplicated: `$TMPDIR` (mac.temp), DerivedData, uv, pip, npm, Homebrew, pnpm, Aerial (Disk rule
  with a `sudo rm` command), Claude temp as a Disk rule.

## Review Focus

1. A user who ticked targets by hand before this version: the saved ticks stay, used again in "By hand" mode.
2. A clone folder full of framework symlinks: the whole folder must go, not leave an empty tree behind.
3. Clones with 0 private bytes are still removed by Clean (honest 0 B gain, never hidden).
4. Disk "Clean" on a Moderate target in Safe mode: it gets ticked, the mode becomes By hand, Overview shows it.
5. Cowork bundle open by another VM process: that process is never stopped.

---

### Task 1: Selection modes

**Files:** `CCCore.h/.m` (`CCSelectionMode`, `CCAutoSelects`), `CCSettings.h/.m` (`selectionMode`, JSON
`selectionMode`: "safe" | "moderate" | "manual", default "safe" also when the key is missing), `CCModel.h/.m`,
`CCPages.m` (Overview "Pick" row), strings, tests.

- `BOOL CCAutoSelects(CCTarget *t, CCSelectionMode mode)`: custom folders yes; Trash never; otherwise
  `enabledByDefault && (risk == Safe || (mode == Moderate && risk == Moderate))`; Careful never; Manual → NO.
- Model: `selectionMode` property; `setSelectionMode:`; auto modes recompute `enabled` from `CCAutoSelects` at launch,
  after a scan and after adding a folder; any hand toggle (target, category, Select none) copies the current ticks into
  `targetStates`, switches to Manual, then applies the change; Manual uses `targetStates`.
- `- (void)includeTarget:(NSString *)identifier` — ticks it (switching to Manual only if the mode does not already
  pick it).
- Overview row: «Выбирать: Безопасное · Безопасное и умеренное · Вручную · Ничего», current one highlighted.
- Test `TestAutoSelection`: Safe picks `dev.npm`, not `mac.caches` (Moderate) nor `dev.huggingface` (Careful) nor
  `mac.trash`; Moderate adds `mac.caches`, not `dev.projects` (off by default); Manual picks nothing; settings
  round-trip "moderate"; a file without the key loads "safe".

### Task 2: One number

**Files:** `CCEngine.m` (Hermes rule parts → target children), `CCCore.m` (`app.hermes` target), `CCDiskPage.m`,
`CCWindow.m`, `CCModel.m`.

- Disk map: a rule part or listed child whose path is a target root gets that `targetId` (so it shows Clean, not a
  trash can, and is not a "safe part").
- `app.hermes` (Apps, Safe): `~/.hermes/cache/uv`, `~/.hermes/cache/pnpm`, `~/.hermes/hermes-agent/.cache`,
  `~/.hermes/image_cache`, `~/.hermes/audio_cache`; Hermes rule gains parts `cache/uv`, `cache/pnpm`.
- Disk summary line = `M().cleanableBytes` with a Clean button that runs `[M() clean]`; row Clean →
  `includeTarget` + Overview + scan when there are no results. Sidebar: the number sits on Overview only.
- Test in `TestDiskMap`: a fake `~/.hermes/cache/uv` is a child with `targetId == app.hermes` and `canDelete == NO`.

### Task 3: New targets and engine features

**Files:** `CCCore.h/.m`, `CCEngine.h/.m`, new `CCProcesses.h/.m`, `build.sh` (test sources), strings, tests.

- `CCTarget`: `idleDays` (roots touched within are dropped; cached 20 s), `deletesWholeRoots` (clean removes each root
  as one item, links never followed), `sharesBlocks` (scan counts `ATTR_CMNEXT_PRIVATESIZE`; `CCScanResult.sharedBytes`
  keeps the rest), `beforeClean` block.
- `CCProcesses`: `+snapshot` (ps), parsers `CCParseElapsed`, `CCParseCPUTime`; `+chromeStarts:`; `+stuck:hermesIdle:`;
  `+coworkVMPids:bundle:`; `+terminate:`; `CCStaleClones(root, starts)`; `CCCoworkNeeded(sessions, idle, &why)`;
  `CCTouchedWithin(path, seconds)`.
- Targets: `browser.chromeclones` (Browsers, Safe, sharesBlocks, deletesWholeRoots),
  `app.coworkvm` (Apps, Moderate, deletesWholeRoots, beforeClean stops its VM),
  `dev.claudetmp` (Developer, Safe, `/private/tmp/claude-<uid>/*`, idle 3 d, whole roots),
  `mac.programtemp` (System, Safe, `/private/tmp/{tmp*,pymp-*,jobs-test-*}`, idle 1 d, whole roots),
  `dev.clang` (Developer, Safe, `$DARWIN_CACHE/clang/ModuleCache`, idle 7 d),
  `dev.hyperframes` (Developer, Safe, `~/.cache/hyperframes/{chrome,fonts}`).
- `CCTargetItem` with `sharesBlocks`: selectable while it has files even at 0 B; status says how much is shared.
- Tests: stale clone found / kept by birthtime (set with `setattrlist`); symlinked clone removed whole; Cowork needed
  by scheduled task / recent change / idle; `idleDays` drops a fresh root; elapsed/cputime parsing; stuck detection on
  a fixture process list.

### Task 4: Stuck processes on Overview

**Files:** `CCModel.h/.m` (`stuckProcesses`, `terminateStuck:`), `CCPages.m` (card), strings.

- Card appears only with findings; each row: what, why, memory, «Завершить» (confirm). Hermes tab → `hb-stop` when
  the script exists, else no button. Refreshed with insights and after a scan.

### Task 5: Verify and ship

- `./build.sh --test` passes; capture Overview/Disk in Russian; numbers equal; a clean lowers them; PR.
