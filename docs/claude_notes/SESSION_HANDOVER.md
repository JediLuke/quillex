# Handover — 2026-08-21

Written to be read cold. Everything here is measured, or explicitly flagged as
unverified.

---

## Where the repos are

| repo | branch | HEAD | state |
|---|---|---|---|
| `quillex` | `feature/external-file-sync` | `90079b0` | committed, clean |
| `scenic-widget-contrib` | `nice_module_attributes` | `d650062` | committed, **pushed** |

`mix.exs` pins contrib at `d650062`. 21 commits in each repo since the previous
handover.

### The pin ritual

Held across twelve contrib commits and twelve re-pins this session, no blank
screens. Push contrib and bump the SHA the moment quillex calls new contrib
code, not at the end of a batch:

```bash
cd ../scenic-widget-contrib && git commit && git push
# bump the SHA in quillex/mix.exs
cd ../quillex && unset QUILLEX_LOCAL_DEPS && mix deps.get && mix compile
```

---

## NEXT STEPS — the queue

Roughly in the order they were asked for. The search pane is close to done;
most of what is left is aesthetic, plus one real bug at the end.

### 1. One scroll system for dropdowns, with a visible scrollbar

**Start here. It is the largest loose end and it is half-built.**

There are currently TWO scroll systems for what is now one component:

  * `IconMenu` scrolls its dropdown through `Reducer.scroll_dropdown/2` and
    `State.max_dropdown_scroll/1`, with the offset baked into
    `dropdown_bounds` so drawing and hit testing read the same map;
  * the search pane's settings panel scrolls its scope tree through
    `SearchPane.State.scroll_scope/2` and a `scope_scroll` field on the PANE,
    which `settings_rows/1` feeds into the `Tree` row's `scroll_offset`.

That happened because the pane's panel was built before the dropdown was
extracted, and the extraction never reached the scrolling. The pane's version
also exists for a real reason worth preserving: rows are rebuilt from the
model every time results land, so an offset kept inside a row would be thrown
away by the next search. Whatever replaces it needs somewhere durable to keep
the offset.

On top of that, neither says it scrolls. The scope tree prints
`▲ 13–24 of 31 ▼`, which is a readout where the thing itself would do, and
`IconMenu`'s clamped dropdowns show nothing at all.

So: move scrolling into `Menu.Dropdown` — offset, wheel, and a real scrollbar
from `Widgex.Scroll.ScrollRenderer` (which already draws bars) and
`Widgex.Scroll.Drag` (which already drags them, since this session). Shown
only when there is overflow. Then delete `scope_scroll` and the readout.

Answering the question that was asked: **a scrollbar, not clickable scroll
buttons.** The clamp-and-scroll mechanism exists and works now; buttons would
be a second mechanism beside a working one, and a bar also says how much there
is, which buttons cannot.

### 2. ~~The View dropdown has no visible scroll~~ — DONE, but read this

Fixed on 2026-08-21. Recorded because the *diagnosis* was wrong twice before
it was right, and the wrong ones are instructive.

There were TWO bugs, not one:

  * a window made smaller left every menu holding the `max_dropdown_height`
    it was built with, because that number is part of the theme and themes
    were only re-pushed on a palette or zoom change. The menu believed it had
    room it no longer had and drew past the viewport;

  * and the wheel never reached it at all. `IconMenu.request_input/2` listed
    `:cursor_pos`, `:cursor_button` and `:key` — no `:cursor_scroll` — and no
    primitive named it either, so Scenic hit-tested the wheel against nothing.
    `scroll_dropdown/2` had been there the whole time with nothing to call it.

**I read the code and concluded it already scrolled and merely lacked an
affordance. It did not, and the person using the editor had tested it.** Read
the code to find out where to look; do not read it to find out what happens.

This also fixed the standing `46_menu_layout` 3px failure, which had
reproduced at `8e4c02d` and passed only in group runs — spex runs resize the
window, so whether the menu was clipped depended on what had run before it.

`67_menu_fits_any_window_spex` is the guard, written as a PROPERTY: it varies
the window across four heights and asserts of every size that each dropdown
stays inside the window, that one too short to fit still scrolls, and that
going back up leaves nothing clamped.

### 3. Square buttons in the search pane

The find popup's buttons are perfectly square; the pane's replace-one and
replace-all buttons are not, and look worse for it. Match the popup.
`State.header_widgets/1` sizes them from `button_size/1` and `button_w`.

### 4. A darker highlight for dropdown rows

The IconMenu dropdown's row highlight has more contrast than the search bar's.
Try the darker treatment in the search pane's panel — and consider whether the
search BAR should move to it too.

The pane maps its palette into menu vocabulary in
`SearchPane.State.dropdown_theme/1`; `item_hover_bg` is the key. It is
currently `theme.button_active` (the accent) — deliberately, because the
obvious choice (`row_hover`) is the same colour as the panel background and
lit nothing at all. Do not go back to that.

### 5. Borders on dropdowns

Try a border on the settings panel again, and on the top-right IconMenu
dropdowns. The panel had an accent border early on, which read as a focused
input; it has an ordinary one now, and no shadow. The shadow was removed on
request but looked good against the buffer — it is one line in
`Menu.Dropdown.render/4` if it comes back.

### 6. More property-shaped spex

`67_menu_fits_any_window_spex` was the user's idea and it immediately paid:
vary the window size, then assert the same few things of every size rather
than picking one and hoping. The shape generalises —

  * vary the SIDEBAR width and assert every pane control stays reachable;
  * vary the chrome zoom the same way (65 covers two points, not a range);
  * vary the result count and assert the pane draws a bounded window at all
    of them.

A case picks a number and hopes it is the interesting one. A property says
what must be true of all of them, and the window-size bug had been sitting
under a suite that only ever tested one size.

### 7. The aesthetic overhaul

Flagged as coming. When it happens, `Menu.Dropdown` is one place and both the
menubar and the search pane follow it.

### 8. Generalising `Submenu`, if wanted

`Menu.Model.Submenu` is still declared and unimplemented. `Tree` now covers the
inline-expanding case, so `Submenu` (a flyout) may simply not be needed —
decide rather than leave it declared.

---

## What this session did

### Dropdowns behave like dropdowns

Three requirements that are obvious the moment they are missing and invisible
the rest of the time. All three were found by USING the editor; none of them
would ever have been written down as a feature.

**Escape puts it away — and puts away the menu, not everything.** It was
handled only where a focused field reported it, and by the time you have been
clicking around a menu the field has not got the keyboard, so nothing happened
at all. Handled once now, in the pane's own key input, which it hears whatever
has focus. Closing the whole pane because a menu happened to be open would
throw away the search as well as the menu; a second Escape still closes it.

*The key atom is `:key_esc`, not `:key_escape`.* Every other component in the
repo already knew that.

**Scrolling somewhere else puts it away**, in the search pane and the top bar
alike. `IconMenu` returned `:noop` for a wheel outside its dropdown, so the top
bar kept its menu up while you read the document underneath.

**Nothing that redraws underneath it lands on top of it.** This one has a
mechanism worth remembering: *a replaced piece of a Scenic graph lands at the
END, which is what puts it on top.* Every other piece of this pane is disjoint
so it never mattered — but the settings panel deliberately overlaps the
results, so results rebuilt after it were drawn over it. Toggling a settings
option is exactly that sequence: the panel redraws for the option, and then the
search that toggle STARTED comes back and rebuilds the body over it. The panel
is now re-rendered whenever anything under it is.

`68_dropdown_manners_spex` guards all three. It waits for the SEARCH rather
than the click, because the click was never the problem, and it measures draw
order the way Scenic resolves it — the root group's child list — rather than by
uid (a primitive does not carry one) or by position in `graph.primitives` (a
map, with no order to read).

### The search pane is responsive

Three steps, each measured before and after.

**Virtualised the body.** It built and drew a row for every match in every
file; ~40 are ever on screen.

| result set | build before | after | primitives before | after |
|---|---|---|---|---|
| 550 rows | 38.9 ms | 3.5 ms | 2180 | 209 |
| 1100 rows | 78.8 ms | 3.5 ms | 4330 | 209 |

**A real loading state.** The store publishes `:debouncing` on the keystroke,
so the three in-flight states are `:idle | :debouncing | :searching | {:done,
…}`. Results are FADED for as long as they are the last answer rather than
this one, and a search with nothing to fade says so in the body.

Faded, not removed: the debounce fires on every character, so a pane that
emptied itself between letters would be blank most of the time you typed at
it. That reasoning is in the store's moduledoc beside the contract.

**Streaming.** Measured on Quillex itself: the tree walk takes 9.8ms, the
first file matches at 4.4ms, the last at ~85ms — so ~95% of the wait was after
the answer's first line was already known. Results now arrive as they are
found: first results on screen ~160ms before the search finishes on a 250-file
fixture.

Partials carry DISK results only; the unsaved-buffer overlay runs once at the
end. Ripgrep declares it cannot stream and yields in one go — and **rg is not
installed here**, so that path stays unexercised.

### The pane's controls actually work now

Every spex it had drove ONE feature. **Features tested one at a time are
features that work one at a time.** `58_global_search_journey_spex` is one
person, one project, one continuous session, clicking only what a person can
see, by the names the pane publishes, believing only what it has DRAWN.

It found four things in a pane with a green suite:

1. the tree/list slider had a dead zone down its middle;
2. a scope row whose directory had children spent every click expanding
   itself, so no folder containing anything could be excluded;
3. every list row said its line number twice and highlighted the wrong ten
   characters;
4. the × cleared the query and took the keyboard with it.

Plus: the scope tree is rooted in the PROJECT, exclusion is inherited, and an
unticked root actually empties the search.

### The scrollbar, and where dragging belongs

The pane's scrollbar could be looked at and not moved — `State` carried the
three `scrollbar_drag*` fields from its first commit and nothing ever read
them. Nothing caught it because **every scroll spex tests the wheel, and the
wheel worked**.

`Widgex.Scrollable` gave hosts scroll state, a wheel and scrollbars, and never
gave them dragging — so SideNav wrote it, TextField wrote it again, and
SearchPane got the fields with no code. It lives in `Widgex.Scroll.Drag` now;
SideNav delegates. **TextField still has its own** and was left alone
deliberately: it works, it is the most used surface in the editor, and its
version has quirks that deserve their own pass.

### Tree and list are two views

They were the same idea twice. `tree` keeps the project's shape (only the
directories a match is in); `list` is the flat run with paths shown. The
per-match view is gone; the list still shows every match without repeating the
filename to do it.

### The dropdown is separated from the bar

`ScenicWidgets.Menu.Dropdown` — `layout/3`, `render/4`, `row_at/2` — owns the
three things that must agree about where a row is. The caller supplies only
the anchor. `IconMenu` is 460 lines lighter and behaves identically; the
search pane's settings ARE menu rows now.

What made it un-reusable was never the drawing: every function took the BAR's
state and read `active_menu` out of it.

`Menu.Model.Tree` is a menu row you can pick a SET out of (the scope tree is
the first customer). `Menu.Model.Segmented` is an either/or with a position
per choice (tree/list is the first customer). Both are generic; both publish
every node or position by name.

### The settings are a popover

A cog on the status bar, and a panel that FLOATS over the results. Three
inline arrangements were tried and all moved something — above the bar pushed
the cog out from under the pointer that clicked it, below the bar shoved the
results, and a header row of its own was the row the cog replaced. It is
narrower than the pane and hung a third/two thirds around the cog, so it reads
as hanging off the button rather than as part of the pane.

The panel claims the pointer over itself, because this pane takes input from
its own primitives and the panel overhangs the buffer.

### Zoom scales the chrome

It didn't. The layout reads the zoom directly so the frames moved, while every
child kept the theme it was created with — 13pt tabs in a bar grown to 52
tall. The repaint fired only on a palette change and pushed only colours.
Every chrome theme is now built by a NAMED function used both to create and to
repaint it.

### The search pane is sized off the file navigator

They shared the sidebar and were sized by different systems: the navigator's
17pt labels against the pane's 13. One function decides it now, and the pane's
own pixels (slider, buttons, caret column) derive from the type rather than
from a memory of 11pt.

### Find what you have highlighted

Select a symbol, press Ctrl+F or Ctrl+Shift+F, and it is in the box. Both
paths seeded from the word under the CURSOR, and project search preferred what
it last searched for — so the second time you did it you got the previous
symbol. Selection wins over both now.

And `Ctrl+Shift+Arrow` now selects a word: `:ctrl` was tested first, so the
combination went down the plain movement branch and the Shift was never
looked at.

---

## The spex

| file | what it holds |
|---|---|
| `41_project_search_spex` | the pane's own controls |
| `57_search_pane_virtualisation_spex` | only the visible window is DRAWN |
| `58_global_search_journey_spex` | the whole journey, front-end only, by name |
| `59_search_loading_state_spex` | samples every 15ms; asserts the ORDER of states |
| `61_search_streaming_spex` | results on screen while still searching |
| `62_search_pane_scrollbar_spex` | the bar can be dragged, and released |
| `63_search_results_tree_spex` | tree keeps the project's shape; list does not |
| `64_search_pane_chrome_spex` | cog, cancel sign, panel, hover, sizing, tree scroll |
| `65_chrome_zoom_spex` | zoom scales the chrome, up AND back down |
| `66_search_from_selection_spex` | find and project search seed from a selection |
| `67_menu_fits_any_window_spex` | PROPERTY: no window size clips or strands a menu row |
| `68_dropdown_manners_spex` | Escape, scroll-away, and nothing redrawing over the top |
| `test/menu_tree_test.exs` | the generic tree row (9 unit tests) |
| `test/word_selection_test.exs` | Ctrl+Shift+Arrow, both halves (6 unit tests) |

Every new assertion was verified by breaking the code and watching it fail.
That is not decoration — it caught two spex that would have passed regardless,
and a hover assertion that would have passed for the wrong reason.

**A loading state, a streaming search and a hover can only be tested by
SAMPLING or by COUNTING.** They are states the pane passes through; a single
look after the fact sees the end of it. And "nothing lit" and "everything lit"
are both bugs, so the hover spex counts rather than checks.

---

## Traps worth keeping

- **Do not `git checkout <file>` to undo a break-test.** It reverts the whole
  uncommitted file. This destroyed finished work three times this session.
- **Do not rebuild while a spex run is in flight.** It kills the run and
  leaves an orphaned `mix spex` holding port 9987, after which nothing starts.
- **Spex fixtures must not live under `test/support/`** — it is compiled into
  the test build. All search fixtures write to `System.tmp_dir!()` now.
- **The spex driver cannot send Ctrl+Shift+Arrow.** It passes `[:ctrl,
  :shift]` and Scenic hands the component `[:shift]`. Confirmed by
  instrumenting the field. Ctrl+Shift+F works, so it is specific to arrows.
- **A change-check that compares the wrong thing is silent.** Three bugs this
  session were a signature missing a field: the scope tick (in the label, not
  the id), the tree scroll offset, and the panel hover.
- **Graph primitives are a map.** No drawn order — sort by translate, or walk
  down from the group you mean. Between two SIBLING pieces, the order that
  matters is the parent group's child list, and a replaced piece goes to the
  end of it.
- **Read the code to find where to look, not to find out what happens.** The
  View menu scroll was diagnosed wrong twice from reading, and right once from
  the person using the editor saying it did not work.
- The pane and the find bar still share a **design but not code**. Six-plus
  fixes have now been made twice.

---

## Known, unfixed

- **Clipboard spex fail against the real system clipboard** (`left: "menu"` is
  another application's content). Measured 2/5 without this session's changes
  and 3/5 with, so: environment, not regression.
- **`04_view_settings`' Line Numbers Toggle** fails in a group run and passes
  alone — the zoom-left-behind hazard.
- **ripgrep is not installed**, so `Backend.Ripgrep` — including its
  `stream/3` — is unexercised. Installing rg is also the single biggest
  remaining win for search latency.
- **TextField has its own scrollbar drag**, not yet migrated to
  `Widgex.Scroll.Drag`.
- **The search pane's panel and IconMenu's dropdown scroll by different
  machinery** — see queue item 1. They are the same component now and should
  not be.
- The scope tree is capped at `@scope_cap` rows and scrolls past it.

## How to work on this

The pane and the menus are now mostly ONE thing —
`ScenicWidgets.Menu.Dropdown` draws both, `ScenicWidgets.Menu.Model` describes
their rows. A change to how a menu row looks or behaves should almost always
land there rather than in a host. Two hosts exist: `IconMenu` (the top bar)
and `SearchPane` (the settings cog). Changing one and not the other is how
they drifted apart in the first place.

The remaining queue is almost entirely aesthetic, and the user has an
"aesthetic overhaul" planned that will touch all of it — worth asking whether
items 3–5 should simply be folded into that rather than done twice.

## Open question from the user, still unanswered

> "do we do syntax highlighting for markdown?"

No markdown lexer in the dependency list, so currently "no". Somebody needs to
check whether `makeup_markdown` exists or whether it means writing a lexer.
