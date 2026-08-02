# Quillex Top-Down Audit

This is a living, observation-first audit of Quillex, produced while browsing
and editing the Quillex repository inside Quillex itself.

The purpose of this document is to preserve findings for a later fixing run.
An entry here is **not** authorization to fix it during the audit. Keep observed
behavior separate from hypotheses, and verify each finding independently
before changing code.

## Method

For each finding, record:

- what a person did and observed;
- what they expected instead;
- the affected product area and likely code boundary;
- whether the behavior has been reproduced independently;
- open questions, without prematurely selecting a fix.

Status vocabulary:

- **Observed** — seen during dogfooding, not yet independently reproduced.
- **Requirement** — desired 1.0 product capability; behavior and component
  contract still need design and acceptance criteria.
- **Reproduced** — repeated with a minimal sequence.
- **Characterized** — relevant execution path and boundaries are understood.
- **Ready for fixing** — acceptance behavior and a regression test are defined.
- **Resolved** — fixed and verified in a later fixing run.

## Current audit scope

The top-down pass currently treats **standalone Quillex** as the primary
product: the normal `QuillEx.App` branch that starts performance monitoring,
RadixCache, buffer supervision, the CLI startup hook, and Quillex's Scenic
viewport.

The Flamelex/hosted branch remains an important architectural concern and is
documented under AUD-010, but it is deferred as a separate integration track.
Nothing in the standalone audit should be taken as validation of hosted boot,
and changes proposed in a later fixing run must be checked against that
contract before landing.

## The Quillex 1.0 system boundary

Quillex 1.0 is not defined by the contents of this repository alone. The
releasable product is assembled from Quillex and its co-developed Scenic
libraries, including at minimum the local Scenic fork, local driver,
`scenic-widget-contrib`, its Widgex layout/scrolling system, and the Spex and
semantic-observation tooling used to validate the result.

Therefore:

- a framework or reusable-widget defect visible in Quillex is a Quillex 1.0
  release concern even when the owning code lives in a sibling repository;
- findings should identify the correct ownership layer rather than patching
  symptoms in Quillex merely to keep changes local;
- reusable components—especially scrollbars, TextField, dialogs, SideNav, and
  layout primitives—must be audited as components, not only through the one
  configuration Quillex happens to exercise;
- fixes in sibling libraries require their own focused tests plus integration
  evidence in Quillex;
- the release must pin or bundle mutually compatible revisions of the entire
  constellation so a green result can be reproduced;
- "the app launches" is insufficient for 1.0 if foundational input, geometry,
  clipping, focus, or component-reuse contracts remain unreliable.

The audit may begin from standalone Quillex top-down, but it is expected to
cross repository boundaries whenever responsibility passes into a reusable
Scenic component or primitive. Those libraries are part of the product being
released, not incidental implementation details.

### Reusable-component standard for 1.0

For a shared component used by Quillex to count as 1.0-ready, audit at least:

- geometry and rendering at multiple frames, content sizes, and DPI/font
  conditions;
- z-order, clipping, transforms, hit-testing, and pointer capture;
- keyboard focus, modal isolation, and one-owner input routing;
- full mouse behavior, including press, drag, release, leaving bounds, and
  interaction between overlapping regions;
- state hydration, update, teardown, restart, and component recreation;
- accessibility/semantic representation sufficient for deterministic testing;
- API ownership: application policy stays in Quillex while reusable mechanics
  stay in the appropriate Scenic library;
- an isolated component test and a real-window Quillex integration scenario.

Scrollbar work is the immediate example. Scroll geometry, rendering, input
ownership, capture, and thumb-drag mathematics are supposed to form a reusable
component contract. AUD-006, AUD-007, AUD-014, and AUD-015 should be evaluated
against that shared contract rather than fixed as four unrelated SideNav or
TextField exceptions.

### Evidence policy for the future fixing run

Every user-observable audit finding fixed for 1.0 should be backed by a Spex
regression that exercises the real Scenic application. For bugs discovered by
dogfooding, the preferred sequence is:

1. reduce the observation to the smallest repeatable user interaction;
2. encode that interaction as a Spex and confirm it fails for the right reason;
3. add focused unit/component tests at the library layer that owns the defect;
4. implement the fix;
5. demonstrate the original Spex and focused tests passing together;
6. run the relevant neighboring scenarios and eventually the full suite.

Spex is required where the contract crosses actual input routing, focus,
hit-testing, z-order, component lifecycle, rendering, or user-visible state.
Lower-level tests remain valuable for exhaustive geometry, reducers, path
identity, and pure state transitions, but they do not substitute for proof that
the assembled editor behaves correctly.

The Spex should assert the product outcome, not merely an internal call. For
example, AUD-022 should open a file through SideNav while that file already has
an inactive tab, then prove:

- the existing tab becomes active;
- no second tab appears;
- the same buffer content and unsaved state remain;
- SideNav selection follows the active file;
- subsequent typing edits the existing buffer.

When a defect belongs to a sibling Scenic library, keep both layers of
evidence: an isolated reusable-component regression in that library and a
Quillex Spex demonstrating the real integration. Test-only escape hatches from
AUD-017 must not be used to repair or bypass the gesture that a regression is
specifically intended to prove.

## Finding index

| ID | Area | Summary | Severity | Status |
|---|---|---|---|---|
| AUD-001 | Window/layout | Manual window resize causes severe lag and apparent instability | High | Observed |
| AUD-002 | Input/save | Ctrl+S appears to save and also inserts `s` into the document | High | Observed |
| AUD-003 | Help | Keyboard Shortcuts menu item has no visible result | Medium | Observed |
| AUD-004 | Editing/input | Ctrl+Z does not undo | High | Observed |
| AUD-005 | Editing/input | Ctrl+U does not perform the expected operation; intended contract is unclear | Medium | Observed |
| AUD-006 | File navigator | Text-under-scrollbar transparency and legibility need an explicit visual contract | Low | Requirement |
| AUD-007 | File navigator | File navigator needs horizontal scrolling for overflowing rows | Medium | Observed |
| AUD-008 | File navigator | Sidebar text is too small relative to editor text | Low | Observed |
| AUD-009 | Top bar/layout | Line/column indicator has a fixed-width layout risk for large values | Medium | Observed |
| AUD-010 | Boot/integration | Flamelex-specific boot flag encodes a generic hosted runtime mode | Medium | Characterized |
| AUD-011 | Dialogs/design | Popups lack a shared visual and interaction language | Medium | Observed |
| AUD-012 | File picker | Save filename input duplicates an inferior text-control implementation | High | Characterized |
| AUD-013 | Dialogs/input | Modal dialogs do not comprehensively isolate application shortcuts | High | Characterized |
| AUD-014 | Scrolling/input | Scrollbar thumb does not remain pinned to the mouse during drag | Medium | Characterized |
| AUD-015 | File navigator/input | Visible SideNav scrollbars do not own pointer input above file rows | High | Characterized |
| AUD-016 | Instrumentation | PerfMonitor broadly suppresses exits and `measure/2` can run work twice | Medium | Characterized |
| AUD-017 | Test architecture | Boundary exports grant privileged controls that can mask product failures | High | Characterized |
| AUD-018 | File navigator/state | SideNav highlight does not follow the active file-backed buffer | Medium | Characterized |
| AUD-019 | Menus/component design | Reusable menus need icons and richer composable item types before 1.0 | Medium | Requirement |
| AUD-020 | Editor/navigation | Basic indentation-based code folding | Low | Requirement |
| AUD-021 | Editor/rendering | Selection highlight is vertically misaligned with the cursor | Low | Characterized |
| AUD-022 | Buffers/files | Reopening an existing filepath creates a duplicate buffer | High | Characterized |
| AUD-023 | Tabs/layout | TabBar degrades when open tabs exceed available width | Medium | Observed |
| AUD-024 | Editor/view state | Restore each buffer's previous scroll position when switching tabs | Low | Requirement |

## Findings

### AUD-001 — Manual resize causes severe lag and apparent instability

**Observation:** Dragging the window edge to resize Quillex manually caused
the application to lag badly. Closing the window during or after this episode
felt as though the application might crash.

**Expected:** Interactive resize should remain responsive enough to provide
clear feedback, and closing the window should complete predictably.

**Implementation context:** `QuillEx.RootScene.handle_input/3` handles each
distinct viewport reshape. A frame change currently makes the renderizer take
its full rebuild path, recreating the layout while preserving cursor and scroll
state. This is relevant context, not yet an established cause.

**Questions for characterization:**

- How many reshape events and full rebuilds occur during a typical drag?
- Is the delay in graph construction, component teardown/startup, semantic
  model publication, driver rendering, or more than one of these?
- Does resize event coalescing already happen in Scenic or the local driver?
- Was the alarming close behavior only delayed shutdown, or did a process
  actually crash?

**Future acceptance evidence:** A sustained manual resize remains responsive;
content, cursor, scroll, and focus survive; close completes normally; and a
performance regression check covers a burst of real reshape events rather than
only one programmatically injected reshape.

### AUD-002 — Ctrl+S saves and also inserts `s`

**Observation:** After editing a buffer, Ctrl+S appears to save it and clear
the unsaved state, but an `s` is also inserted into the document.

**Expected:** Ctrl+S invokes save exactly once and produces no text input.

**Risk:** This can silently modify the file at the moment the user believes
they have safely saved it.

**Implementation context:** Application shortcuts and TextField input are
separate input paths in the current architecture. Similar historical bugs
have involved more than one consumer receiving the same key gesture, but
double delivery or modifier handling has not yet been demonstrated here.

**Questions for characterization:**

- Does the inserted `s` occur before or after the save snapshot?
- Is the on-disk file saved with the extra character, or is the buffer dirty
  again immediately after a correct save?
- Does this happen for both named files and new buffers using Save As?
- Do key-down, key-repeat, and codepoint events take different paths?

**Future acceptance evidence:** A regression scenario checks rendered text,
buffer dirty state, and exact on-disk contents after Ctrl+S.

### AUD-003 — Keyboard Shortcuts menu item does nothing visibly

**Observation:** Opening Help and selecting **Keyboard Shortcuts** produces no
visible response.

**Expected:** Display a popup comparable in quality and behavior to About
Quillex, containing the supported keyboard shortcuts.

**Implementation context:** The Help menu model contains a `shortcuts` item.
The later fixing run should trace its event handling and decide where shortcut
documentation has a single source of truth.

**Future acceptance evidence:** Mouse activation opens the popup; keyboard
activation does too; dismissal restores editor focus; displayed shortcuts
match actual bindings.

### AUD-004 — Ctrl+Z does not undo

**Observation:** After editing text, Ctrl+Z did not visibly undo the edit.

**Expected:** Ctrl+Z undoes the most recent undoable document edit exactly
once. Undo is advertised by the UI and supported by the buffer reducer.

**Questions for characterization:** Determine whether the gesture is not
translated, not dispatched, dispatched twice, rejected by focus routing, or
successfully reduced but not rendered.

**Future acceptance evidence:** Cover typing, deletion, multiline edits,
selection replacement, and the corresponding redo behavior through the real
input pipeline.

### AUD-005 — Ctrl+U expectation is unresolved

**Observation:** Ctrl+U did not perform the operation expected by the tester.

**Expected:** Not yet specified. It may have been expected as an alternate
undo binding, while common editor conventions also assign Ctrl+U other
meanings. Quillex should either implement and document a deliberate binding or
leave it unbound consistently.

**Audit action:** Establish the intended shortcut vocabulary before treating
this as an implementation defect. Include the decision in the proposed
Keyboard Shortcuts popup.

### AUD-006 — Text may render beneath the translucent scrollbar track

**Corrected product direction:** Long file-tree rows may continue rendering
beneath the scrollbar track. When the thumb is elsewhere, seeing text through
the translucent track is visually pleasing and avoids unnecessarily shrinking
the already narrow content area.

The desired contract is therefore not a permanently reserved opaque gutter:

- the track can overlay text with tuned transparency;
- underlying text should remain readable when only the track covers it;
- the thumb must remain visually distinguishable as it passes over text;
- selection/hover backgrounds beneath the bar must not destroy contrast;
- the scrollbar remains above rows for input and hit-testing regardless of
  its transparency (AUD-015);
- content still needs horizontal scrolling when it genuinely exceeds the
  viewport (AUD-007).

**Likely ownership boundary:** The generic `ScenicWidgets.SideNav` and its
scrollable/container primitives in `scenic-widget-contrib`, with Quillex
responsible for supplying a valid frame and theme. Ownership is not yet
confirmed.

**Future acceptance evidence:** Review long names and deep indentation under
the track and thumb at idle, hover, selected, focused, disabled/faded, and
active-drag opacity. Text-through-track should remain attractive and readable;
the thumb and hit region must remain unambiguous.

### AUD-007 — File navigator needs horizontal scrolling

**Observation:** Deep or long file-tree rows exceed the navigator's available
width, but there is no usable horizontal scrollbar.

**Expected:** Overflowing tree content can be explored horizontally, with
behavior consistent with the editor pane: visible horizontal scrollbar,
thumb dragging, and horizontal wheel/Shift+scroll behavior where supported.
The vertical scrollbar gutter remains reserved.

**Design question:** Define the SideNav content width from indentation plus
measured row width, rather than assuming the component frame is the content
extent.

### AUD-008 — File navigator text is too small

**Observation:** Sidebar labels are noticeably smaller than the text in the
editor pane.

**Expected:** File navigator text should be approximately the same readable
size as the current editor text, while retaining a sensible row height and
indentation density.

**Implementation context:** Quillex's current dark SideNav theme specifies a
13 px font and 26 px item height. The editor font should be measured from its
actual configuration before choosing new values.

**Future acceptance evidence:** Visual review at normal and high-DPI scaling,
including deep trees and both scrollbars.

### AUD-009 — Line/column indicator width and tab-bar interaction

**Observation:** The `Ln 1, Col 1` indicator is useful and well liked. It is
unclear whether its black background and internal padding remain sufficient
for values such as `Ln 111, Col 222`.

**Expected:** The entire label remains legible with comfortable padding as
line and column digit counts grow. Any growth must participate deliberately in
top-bar layout because it reduces the width available to the tab bar.

**Implementation context:** The renderizer currently reserves a fixed 110 px
for `CursorPosLabel` and subtracts that, plus the 140 px menu width, from the
tab-bar width.

**Questions for characterization:**

- What digit count fits with the configured font and padding?
- Should the indicator have a fixed maximum width, a measured width, or a
  stable width sized for a documented maximum presentation?
- When horizontal space becomes scarce, should tabs scroll, compress, elide,
  or yield space to the indicator?
- What happens at narrow window sizes and with many open buffers?

**Future acceptance evidence:** Exercise large positions, many tabs, and a
narrow resized window together; assert non-overlap and readable text.

### AUD-010 — Flamelex-specific boot flag encodes a generic hosted mode

**Audit scope note:** Characterized and parked for now. Continue the current
top-down exploration through the normal, standalone child list. Return to
hosted composition after the standalone process responsibilities and public
contracts have been mapped.

**Observation:** `QuillEx.App.start/2` branches on
`started_by_flamelex?/0`, backed by the application setting
`:started_by_flamelex?`. This couples Quillex's boot vocabulary directly to
one consuming application even though the behavior being selected is more
general.

**Current behavior:**

- The normal branch starts `PerfMonitor`, the RadixCache stores, the buffer
  supervision tree, the CLI startup hook, and Scenic with Quillex's viewport.
- The Flamelex branch starts only the RadixCache stores and buffer supervision
  tree. Its comment says that the host manages Scenic.
- The optional development Tidewave/Bandit child is appended after either
  branch, so this is not strictly a complete "backend only" child list.
- `CLI.chdir!()` still runs before the branch in both modes.
- RadixCache starts `Scenic.PubSub` itself in both modes because the stores use
  retained Scenic PubSub sources even when Quillex does not start a viewport.

This confirms that the distinction is primarily **who owns the GUI/runtime
shell**, not whether Quillex's buffer and store architecture is available.
Flamelex wants to reuse that backend and may eventually embed Quillex's editing
surface in its own Scenic tree rather than launch Quillex's standalone window.

**Design concern:** A name such as `run_embedded?` would remove the product
coupling but may still collapse several independent capabilities into an
ambiguous boolean. "Embedded" could mean any of the following:

- start the backend and stores but no Quillex viewport;
- let another application own Scenic while embedding Quillex components;
- run fully headless in the background;
- skip CLI launch behavior and working-directory adoption;
- suppress Quillex-specific development services and instrumentation.

Those modes overlap today but need not remain identical.

**Future design questions:**

- Is the real option `start_gui?`, `runtime_mode: :standalone | :hosted`, or a
  small child-spec API that lets a host select backend and frontend pieces?
- Should Quillex expose a supervised backend subtree for host applications,
  rather than require them to start the entire `:quillex` OTP application with
  a flag?
- Is `ViewStore` meaningful in background-only operation, or should document
  stores and view stores be separately composable?
- Who owns `Scenic.PubSub` when the host already runs Scenic, and is the
  current `ensure_scenic_pubsub/0` contract safe for both startup orders?
- Should performance monitoring also run in hosted mode?
- Which working directory and initial file-navigation path should a host
  provide? The unconditional `CLI.chdir!()` currently gives CLI policy a role
  even in hosted mode.
- How should shutdown behave when Quillex is a library inside another
  supervision tree?

**Audit direction:** Describe the desired embedding contract from the host's
point of view before renaming the flag. The likely end state is a
host-neutral runtime mode or composable child specifications; the audit should
not assume that a single `run_embedded?` boolean is sufficient.

#### Current Flamelex integration (read-only inspection)

Flamelex confirms the original intent, but also shows that the integration is
currently pinned to an older Quillex architecture:

1. Flamelex declares Quillex as a git dependency with `runtime: false`, then
   `Flamelex.App.start_quillex/0` sets `:started_by_flamelex?` before calling
   `Application.ensure_all_started(:quillex)`. This exists specifically to
   prevent Quillex from opening its own viewport before Flamelex can take
   control.
2. Flamelex's `QlxWrap` is the host adapter. Flamelex owns the outer layout,
   menus, splits, active application, and raw-input routing; Quillex is meant
   to own buffer behavior and as much of the editor component as possible.
3. `Flamelex.API.Buffer` and `QlxWrap.Reducer` create, fetch, edit, and save
   buffers by calling Quillex's buffer APIs and `BufferManager` directly.
   Kommander also uses a Quillex buffer as its text model, independently of
   the full editor surface.
4. Flamelex mirrors Quillex `BufRef`s, its own `active_buf`, layout, split,
   font, and save-modal state under `rdx.apps.qlx_wrap`. It publishes and
   renders from Flamelex's own RadixStore rather than following Quillex's
   current retained store snapshots.
5. The wrapper renderizer instantiates
   `Quillex.GUI.Components.BufferPane`, passes a raw `buf_ref`, and manually
   sends frame/state changes to component processes. Current Quillex has
   migrated its editor surface to `ScenicWidgets.TextField` in store-backed
   mode and no longer defines that component at the referenced namespace.
6. Flamelex presently depends on a git-pinned Quillex revision rather than
   the sibling working tree. Consequently, this local Flamelex code may still
   compile against its locked historical Quillex API while not representing
   a working integration with the Quillex code being audited here.

This means the flag itself probably still performs its narrow boot job, but
"does Flamelex embedding work?" and "does it work with current Quillex?" are
different questions. The latter should be considered **unverified and likely
in need of adapter migration**. No Flamelex tests were run during this audit,
and its working tree also contains extensive concurrent changes.

#### Architectural tension exposed by the host

There are presently two control planes for the same documents:

- Quillex's `BufferManager` owns its buffer list and active buffer, while
  `PaneStore` follows that active buffer.
- Flamelex's `QlxWrap.State` separately owns a list of the same `BufRef`s and
  a Flamelex-specific active buffer, including split-pane selection.

Those active-buffer concepts can diverge. A singleton Quillex `PaneStore`
also represents one main pane, whereas Flamelex already models two editor
splits which may display different buffers. The current Quillex architecture
anticipates this conceptually (one PaneStore per pane), but it does not yet
expose a host-facing, multi-instance pane child specification.

The future contract therefore needs to distinguish three reusable layers:

- **Document service:** buffer supervision, lifecycle, reducers, persistence,
  and retained per-buffer sources.
- **Pane control:** a host-configurable pane instance selecting one buffer and
  exposing a stable source/dispatch pair.
- **Standalone shell:** Quillex RootScene, menus, file navigation, dialogs,
  CLI policy, viewport, and window shutdown behavior.

Flamelex should be able to consume the first two without booting the third.
That is more precise than merely changing `started_by_flamelex?` to
`run_embedded?`.

**Future acceptance evidence:** A small host application can start Quillex's
buffer/store backend without naming Flamelex, can optionally mount the editor
surface under a host-owned Scenic runtime, and can stop or restart its Quillex
subtree without affecting the host application. Add a compatibility example
with two host-owned panes showing different Quillex buffers, switching one
without changing the other, and no duplicated buffer-list ownership.

### AUD-011 — Popups need a shared visual and interaction language

**Observation:** Quillex's popups work to differing degrees, but they do not
yet feel like members of one designed system. Colors, typography, spacing,
buttons, borders, overlay treatment, focus indication, dismissal, and general
polish vary between FilePicker, ConfirmDialog, PopupModal/About, search UI,
and future Keyboard Shortcuts documentation.

**Expected:** Opening any Quillex dialog should feel like entering the same
modal system. Dialog purpose and content can differ, but shared visual tokens
and interaction rules should be recognizable.

**Scope to inventory in a later design pass:**

- overlay opacity and whether outside-click dismisses;
- surface, header, footer, border, primary, destructive, hover, and focus
  colors;
- font family, scale, line height, padding, corner radius, and button sizes;
- title placement and close affordance;
- initial focus, Tab/Shift+Tab order, Enter/default action, and Escape/cancel;
- focus restoration after dismissal;
- narrow-window sizing, long text, error display, and destructive-action
  emphasis;
- whether dialog primitives belong in `scenic-widget-contrib` while the
  Quillex theme belongs in Quillex.

**Audit direction:** First produce a popup inventory with screenshots and an
interaction matrix. Standardization should not flatten meaningful differences
such as informational, file-selection, and destructive-confirmation dialogs.

**Future acceptance evidence:** A visual/interaction specification plus
representative tests shared across all modal components, with human review of
the full popup family in one session.

### AUD-012 — FilePicker reimplements a weaker text field

**Observation:** FilePicker works for navigation and selection, but its Save
filename control does not use Quillex's reusable TextField. Its cursor does
not align reliably with text, and mouse editing is substantially less usable
than in the document editor.

**Expected:** Filename editing should inherit the proven single-line subset of
TextField behavior: correct font metrics, click-to-position, selection,
Home/End and arrow movement, insertion/deletion, and visibly correct focus.
Multiline/document-only behavior should be disabled by configuration rather
than reimplemented inconsistently.

**Implementation context:** The current FilePicker owns `filename` and
`filename_cursor`, consumes key/codepoint input itself, draws text using a
plain Scenic text primitive, and places the cursor using the estimate
`String.length(text_before_cursor) * 8 + 8`. Clicking in the footer outside a
button is currently treated as an inert modal-area click; there is no filename
click-to-position path. This directly explains the observed class of cursor
alignment and mouse limitations.

**Architectural question:** TextField is currently strongly associated with
the document/store contract. Determine whether it already has a suitable
controlled/local single-line mode, or whether a small reusable text-input
contract should be extracted without turning filename entry into a buffer
process. Reuse should include behavior and rendering, not necessarily the
entire document backend.

**Future acceptance evidence:** Use variable-width and monospace fonts, long
filenames requiring horizontal reveal, click and drag selection, keyboard
navigation, Unicode, backspace/delete, and focus transitions. Cursor placement
must be based on actual metrics rather than a constant character width.

### AUD-013 — Modal dialogs must own and isolate keyboard input

**Observation:** While a modal text control such as Save filename is active,
editor/application shortcuts generally should not act on the document or open
additional application UI. The dialog needs a deliberately scoped keymap of
its own.

**Expected:** A modal establishes an input boundary:

- text-editing gestures affect the focused modal control;
- Tab/Shift+Tab, Enter, Escape, arrows, and dialog-specific accelerators have
  explicitly defined modal behavior;
- document editing, buffer switching/creation/closing, file operations, and
  unrelated global shortcuts do not fire behind or on top of the dialog;
- exceptional global actions, if any, are explicitly documented.

**Implementation context:** Quillex blurs `:buffer_pane` when opening
FilePicker, and `dispatch_to_active_buffer/2` blocks document actions while an
overlay is visible. That is useful but incomplete. RootScene's Ctrl+N,
Ctrl+O, and Ctrl+W clauses execute before that dispatch guard and call their
application actions directly. Thus modal isolation is currently distributed
across focus state, handler ordering, and per-helper guards rather than
expressed as one policy. Nested/replaced dialogs and accidental buffer actions
need characterization.

**Design question:** Decide whether RootScene performs one early modal-aware
shortcut routing decision, the modal captures relevant input, or both. The
policy must avoid reintroducing historical double-delivery bugs between root
and focused child components.

**Future acceptance evidence:** For every popup, run the normal application
shortcut set while each focusable control is active and assert that no buffer,
file, layout, or dialog state changes except those explicitly allowed by that
popup.

### AUD-014 — Scrollbar thumb drifts away from the mouse during drag

**Observation:** When dragging a scrollbar thumb, the thumb does not move at
the same speed as the pointer. Over the course of the drag, the location where
the user originally grabbed the thumb moves away from the mouse. This was
observed on the current tester's machine and feels unintuitive even though the
document continues to scroll.

**Expected:** The exact point grabbed within the thumb remains pinned beneath
the pointer for the duration of the drag, subject only to clamping at the two
ends of the track. This should hold for both vertical and horizontal thumbs
and for every widget using the shared scrolling implementation.

**Implementation context:** TextField stores the pointer position and content
offset at drag start. During movement it converts pointer delta to content
offset using:

```text
pointer delta / full track length * maximum content offset
```

However, thumb rendering maps maximum content offset onto the thumb's actual
travel distance:

```text
usable thumb travel = full track length - rendered thumb length
```

The thumb cannot place its leading edge across the full track because its own
length must remain inside the track. Using full track length as the drag
denominator therefore predicts exactly the reported behavior: the rendered
thumb moves more slowly than the mouse, with a larger discrepancy for larger
thumbs. This is a strong code-level explanation but has not yet been verified
with instrumentation or a minimal automated reproduction.

**Additional questions:**

- Do TextField's local and store-backed reducer paths duplicate the same
  calculation? Both currently appear to contain scrollbar-drag clauses.
- Does `Widgex.Scrollable` or FilePicker implement thumb dragging separately,
  and if so does it share the defect?
- Is the initial grab offset within the thumb preserved, or only the starting
  pointer and content offset?
- Are track geometry, minimum thumb sizing, line-number gutter, padding, and
  the presence of the other axis calculated identically for hit-testing,
  rendering, and dragging?

**Future acceptance evidence:** Grab near the leading edge, center, and
trailing edge of small and large thumbs; drag slowly and quickly to both
limits; assert that the grabbed local point remains under the pointer. Cover
horizontal and vertical scrolling, both-scrollbar geometry, line numbers,
viewport resize, and at least one other shared-scroll consumer.

### AUD-015 — SideNav scrollbars paint above rows but clicks pass through

**Observation:** Clicking a visible scrollbar in the file navigator activates
the file or directory row beneath it. The scrollbar cannot be reliably clicked
and dragged even though it is visibly drawn over the row.

**Expected:** Scrollbar track and thumb regions are topmost for both rendering
and hit-testing. Pressing the thumb begins a captured drag; moving outside its
original bounds continues the drag; releasing ends capture. No underlying row,
chevron, or file action fires during that gesture. Track clicks should have an
explicit behavior such as page movement or no-op, but must never navigate to a
file underneath.

**Implementation context:** SideNav intentionally requests only keyboard input
at the component level. Mouse input is delegated to primitives using Scenic's
hit-testing. Its renderizer adds the shared scrollbars after scrollable row
content, so their visual z-order is correct. However, shared scrollbar track
and thumb primitives currently declare no `input` styles or SideNav-specific
hit contexts. Each SideNav row contains a full-width rectangle with
`input: [:cursor_button, :cursor_pos]`. Scenic therefore finds the interactive
row beneath a visually opaque but non-interactive scrollbar. This directly
explains the observed file activation.

**Relation to other findings:**

- AUD-006 permits text beneath a translucent track while defining contrast and
  thumb legibility.
- AUD-007 adds horizontal overflow and a horizontal scrollbar.
- AUD-014 requires correct pointer/thumb synchronization once dragging works.
- AUD-015 establishes pointer ownership and gesture capture for those bars.

These should ultimately share one scrollbar interaction contract rather than
receive unrelated local patches.

**Questions for characterization:**

- Should `Widgex.Scrollable` supply generic interactive scrollbar behavior,
  or should it expose geometry/hit results for each host reducer?
- How does Scenic route and capture primitive input during a drag after the
  pointer leaves the thumb?
- Does the same visual-only scrollbar renderer affect FilePicker or other
  consumers?
- Should row hit rectangles stop at the content viewport edge as a second
  line of defense, even when scrollbar input is correctly layered?

**Future acceptance evidence:** Clicking and dragging either scrollbar never
emits a SideNav navigation/expand event. Test thumb, track, scrollbar corner,
row text beneath the gutter, drag outside bounds, and release. Repeat with
both axes present and verify the grabbed thumb point remains beneath the mouse.

### AUD-016 — PerfMonitor failure handling can hide faults or repeat work

**Top-down role:** `PerfMonitor` is a self-contained observer at the edge of
the standalone supervision tree. It consumes Scenic render telemetry, keeps
rolling statistics, exposes stats/reset calls, and optionally wraps measured
functions. No later boot child depends on its state. For purposes of mapping
the boot sequence, it is a leaf and the audit can continue to RadixCache.

**Observation:** Its public API and telemetry callbacks contain several broad
`catch :exit` clauses intended to make missing instrumentation harmless. The
goal is reasonable—monitoring should not bring down the editor—but the current
boundaries also suppress failures that may not mean "monitor unavailable."

**Characterized risk:** `measure/2` executes `fun.()` inside a function-level
`catch`, records the duration, and returns the result. Its fallback for any
caught exit is `fun.()` again. Therefore, if the measured work itself exits
after changing state, writing a file, pushing a graph, or performing another
side effect, instrumentation can repeat that work. The catch does not isolate
only communication with PerfMonitor.

`stats/0` and `reset/0` similarly map all exits from `GenServer.call` to
`:not_running`, potentially conflating a missing process with timeout,
shutdown, or a defect inside the monitor. Telemetry callbacks also swallow all
exits, although their fire-and-forget cast is intended to be best-effort.

**Current exposure:** No production call sites for `PerfMonitor.measure/2`
were found in the current Quillex or `scenic-widget-contrib` sources. Spex
reads and resets monitor statistics, and PaneStore has separate latency
instrumentation. The double-execution risk is therefore dormant today but
would become live as soon as the documented wrapper API is adopted.

**Future design questions:**

- Can measurement use `try ... after` to time work exactly once, with monitor
  delivery performed separately and made best-effort?
- Which failures should the query API distinguish: not started, timeout,
  shutdown, and internal crash?
- Should telemetry attachment/detachment be explicitly tied to the monitor's
  lifecycle and restart behavior?
- Does starting PerfMonitor before Scenic provide value beyond ensuring it is
  attached before the first render, and is that ordering tested?

**Future acceptance evidence:** The wrapped function runs exactly once on
success, raise, throw, and exit; its original outcome propagates unchanged;
monitor absence never changes application behavior; monitor restart does not
duplicate or lose telemetry handlers; and failures remain diagnosable without
making instrumentation load-bearing.

### AUD-017 — Test Boundary capabilities may peek too far behind the curtain

**Observation:** The top-level `Quillex` Boundary exports `Buffer`,
`PerfMonitor`, the pure buffer reducer, and `BufState` for use by the test
helper boundary. These grants let tests control or inspect behavior below the
user interface that Spex ostensibly exercises.

**Actual dependency chain:** Spex files belong to `Quillex.Spex`, which
depends on `Quillex.TestHelpers` but not directly on `Quillex`. The access is
therefore wrapped rather than unrestricted:

- `BufferSwitcher` calls `Quillex.Buffer.switch/1`;
- `FileOpener` calls the application-level `Quillex.API.FileAPI`;
- `Perf` reads and resets `PerfMonitor`;
- `Oracle` constructs `BufState` and folds actions directly through the
  production reducer.

**Most concerning example:** `BufferSwitcher` exists because a real tab click
can be lost. It programmatically repairs the active buffer so later assertions
do not fail misleadingly. This stabilizes unrelated scenarios, but it can also
convert a product failure into a passing test. Its current use was found in
the large integration Spex.

**Important limitation of Boundary:** Boundary is an anti-cheat mechanism only
with respect to the declared policy. It prevents an undeclared dependency, but
a developer—or an LLM responding to a compile error—can simply add the desired
internal module to `exports` or `deps`. The compiler can enforce the allowlist;
it cannot determine whether widening that allowlist preserves the intent of an
end-to-end test.

This is not an argument against Boundary. It is an argument for reviewing
Boundary changes as security/capability changes, especially when generated by
an agent. A new export should explain the exact consumer, why a public or
observable route is insufficient, what the resulting test can no longer
prove, and when the exception should be removed.

**Capability distinctions:**

1. A supported product API may be a legitimate setup seam.
2. Diagnostic observation may be necessary for performance and invariants.
3. Programmatic state control can bypass the behavior under test.
4. The production reducer is useful for delivery conformance, but is not an
   independent oracle for its own semantic correctness.

**Future audit questions:**

- Should strict user-boundary Spex and privileged diagnostic/conformance Spex
  have visibly different tags and rules?
- Should a fallback helper report that the preceding UI gesture failed rather
  than silently repairing it?
- Can privileged setup finish before the scenario while all asserted behavior
  remains user-driven?
- Can model types/reducers live in a dedicated model boundary instead of the
  general application export list?
- Which escape hatches disappear after Scenic input delivery is reliable?

**Future acceptance evidence:** Maintain a capability ledger for every test
helper and Boundary export, including consumers and proof limitations. Review
all Boundary changes explicitly. A strict end-to-end subset must fail when a
real tab click, shortcut, focus transition, or dialog interaction fails.

### AUD-018 — File navigator highlight does not follow the active buffer

**Observation:** Clicking a file in SideNav opens its buffer, but the
corresponding file does not remain visibly highlighted. This makes it unclear
which document the editor is displaying.

**Expected:** When the active buffer is backed by a file represented in the
current navigation tree, that file is visibly selected and its ancestors are
expanded or otherwise discoverable. The highlight follows the active buffer
regardless of how activation occurred: SideNav click, tab click, FilePicker,
CLI startup target, programmatic/public API, or restoration after closing a
buffer.

**Implementation context:** SideNav has its own `active_id` state and a
`{:set_active, item_id}` update API. On a leaf click it attempts to set that
state locally after emitting the navigation event. Quillex, however, creates
the component with `active_id: nil` and no active filepath is included in the
ViewStore snapshot. The RootScene handles `{:sidebar, :navigate, path}` by
opening/focusing the buffer, but no code was found that derives the active
buffer's filepath and pushes it back to SideNav. Thus the application has no
authoritative ongoing synchronization from active document to nav selection.

The exact reason the click-local highlight is not visible still needs a
minimal trace; parent rendering/event order, focus styling, component update,
or later state replacement may be involved. That local symptom should not
obscure the broader missing reverse data flow.

**Ownership question:** BufferManager owns which buffer is active, while the
buffer snapshot owns its source filepath. SideNav owns only presentation of a
selected tree item. Decide where the derived relation
`active buffer -> normalized filepath -> SideNav item id` belongs without
duplicating active-document state in ViewStore.

**Edge cases:**

- active scratch/untitled buffer: clear file selection or show an explicit
  no-file state;
- active file outside `file_nav_path`: clear selection, reveal/navigate to its
  directory, or retain the current tree with an out-of-tree indication;
- two buffers referring to the same normalized file path;
- relative paths, symlinks, case sensitivity, and deleted/renamed files;
- switching active buffers while the sidebar is hidden, then reopening it;
- keeping keyboard focus distinct from active-file selection. A focused row
  and the file currently shown in the editor are not necessarily the same.

**Future acceptance evidence:** Open several files through every supported
route and switch among them using tabs and sidebar navigation. At every step,
exactly the active file is selected when representable; folders reveal it;
scratch and out-of-tree policies are consistent; and highlight synchronization
does not steal keyboard focus or reopen a file.

### AUD-019 — Menu system needs richer reusable composition before 1.0

**Product direction:** Replace placeholder textual menu marks such as `F`,
`E`, `V`, and `?` with coherent icons. More broadly, Quillex 1.0 should include
more expressive menu designs found in mature desktop applications rather than
shipping only the current flat dropdown list.

**Required capability direction:** The shared menu component should be able to
express, theme, lay out, and interact with items such as:

- icon-bearing top-level menus and menu rows;
- ordinary commands with labels and shortcut hints;
- checked/toggled and radio-choice items;
- separators, headings, disabled items, and destructive actions;
- nested or multi-level submenus;
- inline sliders and other compact value controls;
- items whose current value or state updates while the menu is open;
- custom but constrained row content without abandoning standard focus,
  layout, event, and accessibility behavior.

This is intentionally a reusable Scenic component requirement. Quillex should
provide application menu models, actions, and visual theme; the generic menu
library should own geometry, keyboard/mouse navigation, nested-layer behavior,
focus, dismissal, semantic representation, and consistent rendering of the
supported item vocabulary.

**Design risks:**

- Extending the current ad hoc tuple shapes can produce an undocumented mini
  language that is hard to validate and evolve.
- Arbitrary render callbacks may provide flexibility while defeating semantic
  testing, consistent theming, input routing, and layout measurement.
- Nested menus and inline controls intensify the existing z-order and
  close-on-outside-click constraints.
- Sliders inside dropdowns require pointer capture that must not dismiss the
  menu or activate the row beneath them.
- Shortcut labels shown in menus and the future Keyboard Shortcuts popup must
  come from, or be checked against, the actual command/keymap definitions.
- Icons need a reusable asset strategy, sizing/alignment rules, and fallback
  behavior rather than application-specific single-character substitutes.

**Audit/design questions:**

- What is the typed menu-item model and which item types are truly needed for
  1.0?
- Can shared command definitions drive menu rows, enabled/checked state,
  shortcut labels, and shortcut documentation?
- How do keyboard traversal and focus move into/out of nested submenus and
  embedded controls?
- How do menus choose opening direction and remain inside a resized viewport?
- Which styling tokens are shared with the popup/dialog design system in
  AUD-011?

**Future acceptance evidence:** Build a component showcase exercising every
supported item type at normal and constrained viewport sizes, using both mouse
and keyboard. Verify nested z-order, outside-click behavior, slider drag
capture, live state updates, semantic entries, icon alignment, disabled-item
behavior, and focus restoration. Quillex's real menus should then consume the
same public component API without application-specific hit-testing patches.

### AUD-020 — Basic indentation-based folding

**Product direction:** Add deliberately basic code/text folding before 1.0,
based on indentation rather than syntax parsing. Avoid turning this into a
language-server, tree-sitter, or per-language grammar project.

**Proposed bounded behavior:** A line can begin a fold when one or more
immediately following nonblank lines have greater indentation. Folding that
line hides the descendant run until indentation returns to the initiating
level or less. A gutter affordance toggles the region, and an obvious marker
shows that content is hidden.

Provide explicit view commands:

- **Toggle fold at cursor/gutter** — fold or unfold one region.
- **Unfold everything** — clear all fold state for the current pane; this is
  an essential recovery and navigation operation.
- **Fold to level** — establish an outline by keeping content visible through
  a selected indentation depth and folding deeper regions. The UI can expose
  a small useful set of levels rather than arbitrary numeric entry.
- Optionally **fold all** — produce the most collapsed meaningful outline
  while keeping top-level content understandable.

These commands belong under View and may later receive shortcuts. Their labels
and bindings should participate in the shared command/menu/help model proposed
elsewhere in this audit. Defer syntax-derived folds and persistence unless they
prove cheap.

**Architectural constraint:** Folding changes the projection of a buffer, not
the buffer's text. Save, undo/redo, dirty state, search data, and semantic
actions should continue to address source lines. The TextField rendering and
input layers must map between source-line coordinates and visible-row
coordinates. Fold state likely belongs to a pane/view rather than
`Buffer.Process`: two panes showing the same buffer may reasonably have
different regions folded.

**Questions requiring an explicit contract:**

- How are tabs and spaces normalized when comparing indentation?
- Is a fold "level" tree depth or raw indentation columns? Tree depth is
  probably more useful with mixed indentation widths, but requires a
  deterministic region model.
- Do blank lines remain inside a region, and how are trailing blank lines
  treated?
- What happens when the cursor or selection is inside a region being folded?
- Does search reveal a hidden match temporarily, unfold its region, or mark a
  match inside the fold?
- How do edits that change indentation update existing fold regions?
- Do page movement, click-to-position, drag selection, scrollbar content
  extent, line numbers, and `Ln x, Col y` use source lines or visible rows?
- Should folding state survive buffer switches, component recreation, or app
  restart?
- Is the folding mechanic generic enough to belong in the reusable TextField
  while the indentation-region provider is configurable?

**Scope guardrails for 1.0:**

- indentation only;
- manual toggle plus explicit user-invoked fold-to-level; no automatic folding
  on open;
- no syntax awareness or language-specific rules;
- no arbitrary nested outline editor;
- no modification of saved text;
- correctness of cursor/selection/search mapping takes priority over animation
  or elaborate visuals.

**Future acceptance evidence:** Exercise nested indentation, tabs/spaces,
blank lines, file start/end, cursor and selection inside a closing fold,
editing indentation, undo/redo, search into hidden content, buffer switching,
resize, unfold-everything from an arbitrarily nested state, every supported
fold level, and two panes with independent fold state. Repeated fold-to-level
operations must be deterministic and idempotent. Saving a folded document must
produce byte-for-byte the same text as saving it unfolded.

### AUD-021 — Selection highlight sits too high relative to the cursor

**Observation:** The editor's text-selection highlight looks vertically too
high. Its vertical bounds should align with the cursor's visible block/line so
selection and cursor feel like parts of one text-row geometry.

**Expected:** For a given displayed row, cursor, selection highlight, and
search-match highlight share a deliberately defined visual text band. Their
top/bottom alignment should be consistent unless a documented visual reason
requires otherwise.

**Implementation context:** TextField currently renders:

- the cursor at `(display_line - 1) * line_height + 4`, with height
  `line_height`;
- search highlights with the same `+4` vertical adjustment;
- selection highlights at `(line_num - 1) * line_height`, with no adjustment,
  also using height `line_height`.

This four-pixel origin difference directly explains why selection appears
higher than the cursor. Because both rectangles retain full `line_height`, the
issue should be evaluated as shared vertical bounds—not fixed by blindly
adding an offset that could push one rectangle into the following row.

**Design/implementation questions:**

- What is the canonical visual band: full line cell, font ascent/descent box,
  cursor block, or a padded text background rectangle?
- Should cursor height be reduced when shifted down, or should all three
  primitives use a common top and height derived from font metrics?
- Does the correct alignment change for different fonts, font sizes, DPI,
  single-line mode, or wrapped lines?
- Selection rendering currently uses its own line/display mapping; alignment
  review should also verify selection on wrapped rows and while scrolled.

**Future acceptance evidence:** Compare cursor, selection, current/noncurrent
search highlights, and combined selection/cursor states across multiple fonts
and sizes. Verify first/middle/last rows, wrapped lines, scrolling, multiline
selection, and screenshot-level vertical bounds without overlap into adjacent
rows.

### AUD-022 — Opening an already-open file creates a duplicate buffer

**Observation:** With `dev_tools.ex` already open, switching to another tab
and then clicking `dev_tools.ex` in SideNav creates another tab instead of
activating the existing one.

**Expected:** A canonical file identity maps to at most one live editing buffer
by default. Opening that file through SideNav, FilePicker, CLI, or public API
activates the existing buffer and preserves its cursor, selection, scroll,
folds, undo history, and unsaved changes. An explicit future "open another
view" operation may create another pane over the same buffer; it should not
silently create a second independent document state.

**Characterized cause:** `Quillex.API.FileAPI.open/1` contains an intended
deduplication check:

```elixir
BufferManager.list_buffers()
|> Enum.find(fn b -> match?(%{source: %{filepath: ^file_path}}, b) end)
```

But `BufferManager.list_buffers/0` returns `BufRef` structs. `BufRef` is
deliberately minimal and contains only `uuid`, `name`, `mode`, and `dirty?`;
it has no `source`, `filepath`, or document data. The match can never identify
an existing file, so `FileAPI.open/1` always calls the new-buffer path for this
case. The existing-buffer branch also attempts to read `existing.data`, which
would not be available on a `BufRef` if that branch were somehow reached.

This exposes a contract mismatch: FileAPI is asking the buffer-list snapshot
for document identity and content metadata that BufferManager does not publish.

**Risk:** Two independent buffers for one file can diverge. Saving one may
overwrite changes from the other, dirty indicators become ambiguous, and tabs
with identical labels are difficult for people and tests to distinguish.

**Design questions:**

- Should canonical filepath be intentional metadata on `BufRef` and the
  `:radix_buffers` snapshot, or should BufferManager provide a dedicated
  lookup/index without expanding every display reference?
- Where is path canonicalization performed: absolute expansion, `.`/`..`,
  symlinks, case sensitivity, and nonexistent Save-As targets?
- What happens when Save As assigns a filepath already owned by another live
  buffer?
- Should file identity survive external rename/delete, and how is it updated?
- Can the open operation atomically lookup-or-create so two concurrent opens
  cannot race into duplicates?
- Does activating an existing buffer return metadata by fetching its process
  rather than assuming document fields exist on `BufRef`?

**Relation to AUD-018:** Once reopening activates the existing buffer, the
active-buffer filepath should drive SideNav highlighting. Deduplication and nav
selection should share one canonical path identity policy.

**Future acceptance evidence:** Open the same file via relative, absolute,
normalized, SideNav, FilePicker, CLI, and API routes; confirm one buffer UUID
and one tab. Preserve dirty content and editing/view state on activation. Add
concurrent-open and Save-As collision scenarios, plus a deliberate separate
pane/view case that reuses the same buffer rather than duplicating document
state.

### AUD-023 — TabBar does not handle overflow clearly or reliably

**Observation:** When more tabs are open than fit in the available top-bar
width, TabBar does not present or navigate them well. This becomes more
noticeable because the cursor-position label and menu reserve fixed portions
of the same row (AUD-009).

**Expected:** Every open buffer remains discoverable and activatable; the
active tab remains visible; tab labels and close targets do not paint or accept
input outside the tab viewport; and overflow behavior is understandable
without trial-and-error. While the pointer is over the tab strip, ordinary
mouse-wheel/trackpad scrolling should move horizontally through the tabs.

**Implementation context:** The reusable TabBar already models variable tab
widths, a `scroll_offset`, maximum scroll extent, wheel scrolling, and label
truncation. However:

- no explicit clipping/scissor boundary is apparent around the rendered tab
  groups;
- overflow is navigated by wheel scrolling with no visible affordance that
  more tabs exist;
- the reducer already converts vertical wheel delta into horizontal
  `scroll_offset`, but its scroll handler does not itself check that the
  pointer is inside TabBar; correct delivery therefore depends on Scenic's
  positional routing and component transforms rather than one explicit shared
  hover/geometry rule;
- changing `selected_id` through `{:set_tabs, tabs, selected_id}` does not
  appear to adjust `scroll_offset` to reveal the selected tab;
- TabBar competes with fixed-width siblings rather than participating in a
  documented responsive top-bar policy;
- current Spex buffer-management coverage checks tab counts and ordinary
  switching, not a deliberately overflowing bar.

**Close-button failure mode:** When tab groups overlap visually or extend
outside the visible tab frame, close icons and their hitboxes become ambiguous
or difficult to use. A close gesture must resolve to exactly the topmost,
visible tab whose close control is drawn beneath the pointer. Hidden/offscreen
tabs must not contribute hit targets inside the visible strip, and clicking a
close icon must never select or close a neighboring tab because their logical
bounds overlap after scrolling.

These are implementation observations, not yet a complete explanation of the
specific poor behavior seen during dogfooding.

**Design questions:**

- Should overflow use wheel/trackpad scrolling, edge buttons, an overflow
  menu, compressed tabs, or a combination?
- Should horizontal trackpad delta be honored directly while vertical wheel
  delta is mapped horizontally, and what direction feels natural on each
  platform?
- How is the active tab automatically scrolled fully into view after opening,
  switching, closing, restoring, or resizing?
- What minimum useful label/close-target width should be preserved?
- Should pinned/dirty tabs or the active tab receive priority?
- How do keyboard commands traverse tabs that are currently offscreen?
- How should TabBar share width with a growing line/column label and richer
  menus at narrow window sizes?

**Future acceptance evidence:** A Spex should open enough distinct files to
overflow the bar, activate first/middle/last tabs through multiple routes,
close visible and offscreen tabs, and resize narrower/wider. Assert that the
active tab is visible and correctly highlighted, overflow is discoverable,
labels and close hitboxes are clipped to the tab frame, neighboring top-bar
components remain usable, and no tab becomes unreachable. Scroll over the tab
strip in both directions and prove tabs move horizontally; send the same wheel
gesture over the editor, file navigator, cursor label, and menus and prove it
does not move the tab strip. Exercise close icons at both clipped edges and
with partially visible tabs, asserting the exact intended buffer closes once.

### AUD-024 — Remember scroll position per buffer and pane

**Product direction:** When switching away from a buffer and later returning,
restore the part of that document the user was viewing instead of retaining an
unrelated scroll offset or returning to the top. This is particularly valuable
when using Quillex to browse several source files.

**Expected behavior:**

- each open buffer remembers its most recent horizontal and vertical scroll
  position in a given pane;
- switching buffers restores that position without visible jumping through an
  intermediate location;
- the restored offset is clamped if content, word wrap, font, sidebar width,
  folding, or viewport geometry changed;
- cursor visibility has an explicit policy: restoring the view should not
  immediately be defeated by generic "scroll cursor into view" behavior when
  the cursor was intentionally offscreen, unless Quillex defines that the
  cursor must always remain visible;
- closing a buffer discards its transient view state unless session restoration
  later defines persistence.

**Architectural constraint:** Scroll offset is not document content and should
not make a buffer dirty or enter undo history. It also should not necessarily
live globally in `Buffer.Process`: two panes displaying the same buffer may be
scrolled to different places. The natural identity is approximately:

```text
{pane identity, buffer UUID} -> view state
```

That view state may eventually include scroll, folds (AUD-020), and other
presentation-only details. The design should avoid leaking short-lived
TextField process state into RootScene assigns merely to survive a switch.

**Implementation context:** PaneStore currently keeps the TextField component
and pane source stable while switching which buffer snapshot it republishes.
That removes component recreation, but a single component-local scroll value
does not by itself provide a separate remembered offset for every buffer. The
switch protocol needs a deliberate save/restore seam at the pane/view layer.

**Questions:**

- Is the remembered anchor an absolute pixel offset, first visible source
  line plus intra-line offset, or both? Line-based anchors survive font/frame
  changes better; pixels preserve exact placement when geometry is unchanged.
- Should cursor movement while a buffer is inactive alter its remembered view?
- How does restoration interact with search navigation, fold-to-level, word
  wrap, resize, reload from disk, and edits above the viewport?
- Should horizontal offset reset when word wrap becomes enabled?
- Is view state retained only for live buffers in memory for 1.0, with session
  persistence explicitly deferred?

**Future acceptance evidence:** A Spex should open multiple long and wide
files, establish distinct vertical and horizontal positions, switch repeatedly
through tabs and SideNav, and verify each position returns independently.
Repeat after resize, content edits, word-wrap changes, and closing/reopening a
buffer. A two-pane component scenario should prove independent positions for
the same buffer without changing document state or dirty status.

## Cross-cutting themes emerging

These are themes to investigate, not conclusions:

1. **One gesture, one owner.** Ctrl+S and Ctrl+Z should be audited across root
   shortcuts, focused component input, codepoint delivery, and menu actions.
2. **Layout has a cost model.** The correctness-oriented full rebuild strategy
   may need explicit performance constraints for continuous resize.
3. **Scrollable means two-dimensional.** SideNav needs a clearly defined
   content viewport, scrollbar gutters, clipping, and horizontal extent.
4. **Top-bar children compete for finite width.** Cursor status, tabs, and
   menus need an explicit responsive-layout policy rather than independent
   fixed widths.
5. **Documentation should be executable.** The future shortcuts popup should
   not drift away from the bindings and menu labels it documents.

## Dogfooding session notes

When adding observations, preserve the raw experience even if the eventual
cause is elsewhere. Record the file being browsed, whether the buffer was new
or file-backed, focus location, visible panels, and the shortest reproduction
sequence known. UX uncertainty—such as believing the app was about to
crash—is valuable evidence about feedback and responsiveness even when no
crash occurred.
