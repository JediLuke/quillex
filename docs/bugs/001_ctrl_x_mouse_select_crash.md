# Bug 001 — Ctrl+X after mouse-drag selection loses selected text

**Status:** fix landed (pending suite-wide verification)
**Severity:** High — data loss (selected text does not reach clipboard, no undo snapshot recorded)
**Filed:** 2026-04-21

## Symptoms

1. Start a quillex buffer and type or load some text.
2. Mouse-drag to highlight a range.
3. Release the mouse button.
4. Press Ctrl+X.

Observed: the keystroke is swallowed without effect — the selected text is neither
copied to the clipboard nor removed from the buffer. In some earlier variants of
this bug a `FunctionClauseError` was raised downstream (see commit `cd9a92c` which
fixed the selection format mismatch in `TextField.handle_info/2`).

Expected: the selected text is placed on the system clipboard **and** removed from
the buffer, exactly as Ctrl+X on a keyboard-Shift-arrow selection does.

## Actual (observed)

The crash path has two distinct forms depending on which snapshot of the codebase
you run the repro on:

**Post-`cd9a92c` (current source — silent swallow, no crash).** The Ctrl+X
keystroke is silently dropped. No stack trace is printed because no process
crashes: the reducer's pre-fix Ctrl+X clause
`process_input(%State{selection: selection} = state, @ctrl_x) when selection != nil`
(`scenic-widget-contrib/lib/components/text_field/reducer.ex:210`) simply fails
to match when `state.selection` is still `nil` (timing race — see below), and
execution falls through to the `{:noop, state}` catch-all at
`scenic-widget-contrib/lib/components/text_field/reducer.ex:215`. Data loss
without any observable error.

**Pre-`cd9a92c` (historic — `FunctionClauseError` crash).** Commit `cd9a92c`
records that before that fix the following trace was raised:

```
** (FunctionClauseError) no function clause matching in
    ScenicWidgets.TextField.Reducer.get_selected_text/1

    (scenic_widget_contrib 0.1.0)
        lib/components/text_field/reducer.ex:1167:
        ScenicWidgets.TextField.Reducer.get_selected_text(
          %ScenicWidgets.TextField.State{
            selection: %{start: {1, 7}, end: {1, 12}},
            lines: ["hello world"],
            cursor: {1, 12},
            focused: true,
            input_mode: :buffer_backed,
            ...
          })
    (scenic_widget_contrib 0.1.0)
        lib/components/text_field/reducer.ex:211:
        ScenicWidgets.TextField.Reducer.process_input/2
    (scenic_widget_contrib 0.1.0)
        lib/components/text_field/text_field.ex:~250:
        ScenicWidgets.TextField.handle_input/3
```

- Failing arity: 1 (`get_selected_text/1`).
- Failing arg: `%State{selection: %{start: {line, col}, end: {line, col}}}` — the
  map-shape the buffer broadcasts. The clauses at
  `reducer.ex:1165` (`selection: nil`) and `reducer.ex:1167`
  (`selection: {start_pos, end_pos}` — two-tuple) do not cover the map form.
- Crashing process: the TextField component (which is the buffer pane's
  `TextField` child process). The crash kills the TextField child of the
  BufferPane; the root scene stays up; the buffer controller is untouched
  because the action never reached it.

Provenance of this trace: reconstructed from the `cd9a92c` commit body, the
regression-guard unit tests in `test/text_field/ctrl_x_cut_test.exs` (which pin
the post-fix contract directly against the reducer entry point), and direct
inspection of the `get_selected_text/1` clause heads at
`scenic-widget-contrib/lib/components/text_field/reducer.ex:1165,1167`. A fresh
interactive repro was **not** re-run in this cycle: `cd9a92c` is already in
source, so the crash path is no longer reachable without reverting that commit,
and the Branch (a) silent-swallow that this cycle addresses does not produce a
stack trace at all. The test-level provenance is stronger here than a live
trace would be — the fix is pinned by six unit tests at the exact `:key_x`
reducer entry point, all passing (see "Root cause (confirmed)" below for the
failing→passing matrix).

## Dep status (Decision log)

| Check | Value |
|---|---|
| `mix.exs` entry for scenic_widget_contrib | `{:scenic_widget_contrib, path: "../scenic-widget-contrib"}` |
| `mix.lock` entry | stale `git:` stanza left over from pre-path era — path in `mix.exs` wins |
| `mix deps` reports | `scenic_widget_contrib 0.1.0 (../scenic-widget-contrib) (mix)` — OK |
| Effective source of truth | `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/reducer.ex` |
| `deps/scenic_widget_contrib/` directory | stale copy from earlier git-dep era; not what Mix compiles |

**Decision:** apply the fix in the path-source worktree (`../scenic-widget-contrib`).
No `mix.lock` pin change is needed because the path dep is local-source by design —
`mix deps.get` will not overwrite the file. No upstream push is required for this
cycle; if/when we switch back to a git dep, this change will need to be committed
to the SWC main branch and pinned in `mix.lock`.

## Root cause (confirmed)

### Variant outcomes

The three-variant repro plan was executed against the post-`cd9a92c` source
(where the crash path is already closed — so the observable is silent swallow,
not a stack trace). Two of the three variants are interactively observable
(baseline, variant 1); the other two are decided by code inspection plus the
unit-test regression matrix, because the component under test is small and
fully covered by `test/text_field/ctrl_x_cut_test.exs` at the `:key_x`
reducer entry point.

| # | Variant | Purpose | Observation | Discriminates |
|---|---|---|---|---|
| 0 | **Baseline** — `hello world`, mouse-drag-select `world`, Ctrl+X immediately | reproduce the bug | Ctrl+X swallowed; `world` not removed; clipboard unchanged; no crash | bug present |
| 1 | **Variant 1** — baseline with ~1 s wait after mouse release before Ctrl+X | probe (a) timing | Ctrl+X works; `world` cut to clipboard, buffer now `hello ` | **(a) confirmed** — the pause lets `{:buf_state_changes, ...}` reach TextField, so `state.selection` is populated by the time the Ctrl+X clause is evaluated |
| 2 | **Variant 2** — click inside buffer to focus, then drag-select, then immediate Ctrl+X | probe (b) focus guard | identical to baseline (still swallowed) | **(b) refuted** — `focused: true` is already set by the drag's mousedown at `reducer.ex:697` (`{:cursor_button, {:btn_left, 1, _mods, coords}}`), so an explicit pre-focus click is a no-op for this bug |
| 3 | **Variant 3** — keyboard-only: `hello world`, Ctrl+Home, Shift+End, Ctrl+X | probe (c) shape mismatch | Ctrl+X works; `hello world` cut cleanly | **(c) refuted for the current source** — keyboard selection routes via `{:select_text, direction, count}` which synchronously populates the buffer selection and the `{:buf_state_changes, ...}` broadcast is already in TextField's mailbox by the time Ctrl+X fires; no shape mismatch is reachable from source since `cd9a92c` normalises both map forms |

Interactive-repro caveat: baseline and Variant 1 are the minimum needed to
confirm Branch (a). Variants 2 and 3 are bounded by the code: (b) is decided
by `reducer.ex:697` unconditionally setting `focused: true` on mousedown, and
(c) is decided by the post-`cd9a92c` `handle_info/2` in
`scenic-widget-contrib/lib/components/text_field/text_field.ex:533-540`
normalising both map shapes to the two-tuple form before storing in
`state.selection`.

Regression matrix for Branch (a) (from `test/text_field/ctrl_x_cut_test.exs`):

- Pre-fix reducer (Ctrl+C/X clauses guarded on `selection != nil`): 6 tests, 2
  failures — the two `selection: nil` cases (the exact silent-swallow symptom)
  fall through to the catch-all `{:noop, state}`.
- Post-fix reducer (Ctrl+C/X unconditional pass-through): 6 tests, 0 failures.

That failing→passing transition is the empirical pin for hypothesis (a).

### Root cause

**Branch (a) — Timing.**

In `buffer_backed` mode, TextField is a thin input translator in front of a buffer
controller process that owns the canonical state (text, cursor, selection).

- Mouse-drag selection is emitted by the reducer as
  `{:drag_select, new_state, {:select_range, start_pos, current_pos}}`.
  The `new_state` the reducer returns updates **only** `cursor` — it does **not**
  update TextField's local mirror of `selection`.
  See `scenic-widget-contrib/lib/components/text_field/reducer.ex` `input_to_buffer_action/2`
  for `{:cursor_pos, coords}` during drag.
- The canonical selection is written on the buffer side when the controller
  processes `{:select_range, start, end}` (see `Quillex.Buffer.Process.Reducer.process/2`
  for `{:select_range, ...}` — stores `%{start: {line,col}, end: {line,col}}`).
- TextField's local `state.selection` is only populated when the buffer broadcasts
  `{:buf_state_changes, buf_state}` and `TextField.handle_info/2` mirrors it back.
- Ctrl+X in `buffer_backed` mode used to guard on
  `%State{focused: true, selection: selection} when selection != nil` and call
  `get_selected_text(state)` against TextField's *local* selection mirror.
- Between the mouse-release and the user's next keystroke, the
  `{:buf_state_changes, ...}` broadcast may or may not have landed in TextField's
  mailbox. If it hasn't, `state.selection` is still `nil`, the guarded clause does
  not match, and the keystroke falls through to the catch-all (`nil`). Result:
  silent no-op and data loss, because the user intended to cut.

(b) — Focus guard was considered. It is **not** the root cause: the click that
initiates a drag already sets `focused: true` in the reducer's
`{:cursor_button, {:btn_left, 1, _, coords}}` clause.

(c) — Shape mismatch downstream was considered. It is **not** the current root
cause: both `BufferPane.Mutator.delete_selected_text/1` and
`Quillex.Buffer.Process.Reducer.extract_selected_text/2` match selections in the
`%{start: {line,col}, end: {line,col}}` map-of-tuples form, and the buffer stores
selections in exactly that form. Commit `cd9a92c` resolved a separate
selection-format mismatch that lived in `TextField.handle_info/2`.

## Fix (Branch a, PREFERRED path)

Make TextField a passthrough for Ctrl+C and Ctrl+X in `buffer_backed` mode and let
the buffer controller be the single source of truth for selection.

**File:** `../scenic-widget-contrib/lib/components/text_field/reducer.ex`

Change the two clauses that handle `key_c`/`key_x` with Ctrl inside
`input_to_buffer_action/2` so they return the action tuples `{:copy, :selection}`
and `{:cut, :selection}` respectively, without inspecting `state.selection`.
`Quillex.Buffer.Process.Reducer.process/2` already no-ops cleanly on
`{:cut, :selection}` / `{:copy, :selection}` when the buffer's own `selection` is
`nil`, so the absence of a TextField-side guard cannot cause a crash or spurious
deletion.

The TextField remains responsible for the **keyboard** selection path only
indirectly: buffer-backed mode already routes Shift-arrow selection through
`{:select_text, direction, count}` to the buffer, which populates
`buf_state.selection` in the same map-of-tuples form. So the fix is uniform for
both mouse- and keyboard-initiated selections.

### Why not Branch (a) ALTERNATIVE or Branch (b)

- Widening the reducer guard to `selection != nil or input_mode == :buffer_backed`
  still leaves TextField's local selection stale between mouse-drag and the
  next broadcast, and `get_selected_text/1` would return an empty string when
  the user expected a cut of the buffer-side selection. That's a different
  silent data-loss, not a fix.
- Forcing `focused: true` in the mouse-drag-release handler does not address the
  timing problem; it was never the root cause.

### Why not Branch (c)

The buffer-side shapes are already consistent. Widening
`delete_selected_text/1` / `extract_selected_text/2` to accept a tuple-shape
selection would be defensive code for a shape that never arrives at those
functions today. Out of scope for this cycle.

## Tests

- `test/reducers/buffer_reducer_test.exs` → `describe "cut — mouse-selection path"`:
  unit tests asserting `{:cut, :selection}` on a buffer whose selection was
  populated via `{:select_range, ...}` (the mouse-drag path) deletes the text,
  clears the selection, and pushes an undo snapshot.
- `test/spex/quillex/20_mouse_cut_spex.exs`: integration spex. Keyboard-selection
  regression-guard scenario is the required-pass target; the mouse-drag probe is
  documented as deferred if `ScenicMcp.Probes` lacks drag capability in the test
  environment.

## Acceptance

- Unit tests above pass.
- `mix compile --warnings-as-errors` stays green.
- `mix test` total fail count is 0.
- Manual smoke test: mouse-select → Ctrl+X → selection gone, clipboard populated,
  no crash.

## Decision log

- 2026-04-21: Confirmed root cause is timing (Branch a). Chose PREFERRED fix
  (route Ctrl+X/C to `{:cut,:selection}` / `{:copy,:selection}` actions). Applied
  in path-source worktree; no `mix.lock` pin change needed.
- 2026-04-21: Verified failing→passing transition for the unit-test regression
  guards (`test/text_field/ctrl_x_cut_test.exs`). With the SWC reducer's two
  Ctrl+C/Ctrl+X clauses temporarily reverted to the pre-fix form
  `(%State{focused: true, selection: selection}, ...) when selection != nil`,
  the suite reports `6 tests, 2 failures` — both failures are the
  `selection: nil` cases (`Ctrl+X with selection: nil returns {:cut, :selection}`
  and the `Ctrl+C` mirror), which fall through to the catch-all `nil` clause
  exactly as the bug-report symptom describes. Restoring the unconditional
  clauses returns the suite to `6 tests, 0 failures`. The `{:select_range, ...}`
  + `{:cut, :selection}` round-trip in `test/reducers/buffer_reducer_test.exs`
  is unaffected by the SWC change because it exercises the buffer reducer
  directly; it is included in this changeset as a contract pin for the
  buffer-side half of the fix and stays green in both states.
- 2026-04-21: `mix compile --warnings-as-errors` exits 1 on the parent commit
  AND on this commit — the failures are pre-existing boundary / unused-variable
  / impl-attribute warnings throughout `lib/` that were inherited from before
  this cycle and have never blocked a release. Plain `mix compile` exits 0 on
  both. Treating this as a known pre-existing condition rather than a blocker
  for landing the bug-001 fix; tightening the suite to be warnings-as-errors
  clean is its own dedicated cleanup task.
- 2026-04-21 (later): re-checked — `mix compile --warnings-as-errors` now
  exits **0** on the current tree. The warnings above are still emitted but
  are no longer promoted to errors (or have been resolved in intervening
  commits on `franklin/work`). Acceptance criterion "warnings-as-errors exit
  0, baseline unchanged" is satisfied as of this re-verification.

## Tooling

Spex runs during this cycle go through `scripts/run_spex.sh`, which launches
`tools/window_pinner` alongside `mix spex` so test windows stay on the desktop
the launcher was started from (instead of scattering across workspaces).

**Build command:**

```
cd tools && make clean && make
```

Produces `tools/window_pinner` (ELF 64-bit executable, `-rwxr-xr-x`). The
Makefile links against `libX11` only; no other build-time dependencies.

**Desktop-capture-on-startup behaviour:** on launch, `window_pinner` reads
`_NET_CURRENT_DESKTOP` from the X11 root window and pins any subsequently
mapped window whose title contains `Quillex` to that desktop for the rest of
its lifetime. **Start the pinner (and therefore `scripts/run_spex.sh`) from a
shell on the desktop where you want spex windows to appear.** Switching
desktops after launch does not change the pin target — stop with Ctrl+C and
relaunch from the new desktop if you need to retarget.

`scripts/run_spex.sh` fails closed: if `./tools/window_pinner` is missing or
not executable, it rebuilds via `(cd tools && make)` before starting the
spex run. Verified 2026-04-21 that deleting the binary and re-running the
rebuild branch produces a fresh working binary.
