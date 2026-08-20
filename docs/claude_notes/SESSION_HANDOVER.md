# Handover — 2026-08-20

Written to be read cold. Everything here is measured or explicitly flagged as
unverified.

---

## Where the repos are

| repo | branch | HEAD | state |
|---|---|---|---|
| `quillex` | `feature/external-file-sync` | `8c9a172` | committed, clean |
| `scenic-widget-contrib` | `nice_module_attributes` | `11f7ea7` | committed, **pushed** |

`mix.exs` pins contrib at `11f7ea7`. Verified compiling and running spex with
`QUILLEX_LOCAL_DEPS` **unset**.

### The pin ritual

Unchanged, and it held all session — five contrib commits, five re-pins, no
blank screens. Push contrib and bump the SHA the moment quillex calls new
contrib code, not at the end of the batch:

```bash
cd ../scenic-widget-contrib && git commit && git push
# bump the SHA in quillex/mix.exs
cd ../quillex && unset QUILLEX_LOCAL_DEPS && mix deps.get && mix compile
```

---

## What this session did: the search pane is responsive, and its controls work

The task was the three-step plan in the previous handover. All three are done.

### 1. The body is virtualised

`SearchPane.Renderizer` built and drew a row for every match in every file —
~2,500 primitives for 500 results, of which ~40 are ever on screen. Rows are a
uniform height, so the visible window is arithmetic.

| result set | build before | after | primitives before | after |
|---|---|---|---|---|
| 550 rows | 38.9 ms | 3.5 ms | 2180 | 209 |
| 1100 rows | 78.8 ms | 3.5 ms | 4330 | 209 |

`State.visible_rows/1` replaces `rows/1` on the drawing path; `row_count/1`
counts without building; `rows_window/3` skips whole files by arithmetic. Hit
testing is an index into one built row. Semantic registration publishes the
window, not the result set. `scroll_to` stays a transform inside a 6-row
overscan and rebuilds the window past it.

### 2. A real loading state

The store now publishes `:debouncing` on the keystroke, so the three states are
`:idle | :debouncing | :searching | {:done, …} | {:error, …}`. The pane draws
all three: the status line says "typing…" / "searching…" / the count; results
are **faded** for exactly as long as they are the last answer rather than this
one; and a search with nothing to fade says "Searching…" in the body.

Faded, not removed. The debounce fires on every character, so a pane that
emptied itself between letters would be blank most of the time you were typing
at it. The reasoning is in the store's moduledoc beside the contract — if you
disagree it is one line in `render_row`.

Side benefit: `search_done?` in spex 41/57/60 could previously pass on the
PREVIOUS search's `{:done, …}` during the debounce window. It cannot now.

### 3. Results stream in as they are found

Measured on Quillex itself, before writing any of it:

```
walking the tree alone        9.8 ms   (466 files)
until the FIRST file matches  4.4 ms
until the LAST               ~85 ms
```

~95% of the wait was after the answer's first line was already known. The walk
was lazy all along — `Backend.Elixir` built a `Stream` and ran it to the end
before anyone saw a match.

`Project.search_streaming/4` consumes that stream, reporting on the first match
and then at most every 60ms. The store publishes each report exactly like a
finished search except the status still says `:searching` — so step 2's fade
draws partials faded, knowing nothing about streaming.

```
250-file fixture: the walk takes ~300 ms
first results on screen ~160 ms before the search finished
```

Three things to know:

- **Partials are disk results only.** The unsaved-buffer overlay runs once at
  the end; per batch it would fold the same buffer's matches in repeatedly. A
  provisional answer that is *wrong* is worse than one that is incomplete.
- **Ripgrep declares it cannot stream** and yields its whole result in one go.
  `System.cmd` collects all output before parsing, so there is no midpoint —
  and rg finishes inside the debounce anyway. **rg is not installed here**, so
  that path is untested and the Elixir walk is what actually runs.
- **The scope tree is cached** between snapshots (`SearchPaneModel.build/2`
  takes the previous model). It cost 8.9ms of walking the project on every
  publish to rebuild something that changes only when the project or the
  exclusions do. Without it, streaming would pay for each partial with a full
  tree walk.

---

## The bugs, and the spex that found them

The pane had a green suite and three controls that did not work. Every spex it
had drove ONE feature: set the store, click one control, check one flag.
**Features tested one at a time are features that work one at a time.**

`58_global_search_journey_spex` is a JOURNEY — one person, one project, one
continuous session. It opens the pane with the keyboard, types the query a
character at a time, and from there touches nothing but controls a person can
see: clicked **by semantic name**, believing only what the pane has **drawn**.
No store is called, no state is set.

It found four things:

1. **The tree/list slider had a dead zone down its middle.** It resolved a
   click to a half and selected that half, so clicking the centre of a 74px
   control chose the position it was already in and sent nothing. It is one
   control with two positions, so a click now flips it.
2. **A scope row whose directory had children spent every click expanding
   itself**, so no folder with anything in it could be excluded — the entire
   job of a scope tree. The triangle is now its own control
   (`search_pane_scope_expand_<path>`): triangle expands, row ticks.
3. **Every list row said its line number twice** (`README.md:3  3  find the
   needle`) and highlighted ten characters left of the match.
4. **The × cleared the query and took the keyboard with it** — type after
   clearing and nothing happened.

Plus, on the quillex side:

- **The scope tree is rooted in the PROJECT**, expanded by default, so "search
  nothing but this" and "search everything again" are one click.
- **Exclusion is inherited.** A file drawn with a tick under a folder drawn
  without one was the tree contradicting itself.
- **An unticked root empties the search.** Both backends deliberately always
  walk the root (so a stray glob cannot silently empty every search), so
  `Search.Project` answers it once above both. Ripgrep would otherwise have
  ignored the click entirely — its glob for the root is `!/.`.

---

## The spex now covering this

| file | what it holds |
|---|---|
| `41_project_search_spex` | the pane's own controls, as before |
| `57_search_pane_virtualisation_spex` | only the visible window is DRAWN; scrolling moves it |
| `58_global_search_journey_spex` | the whole journey, front-end only, by semantic name |
| `59_search_loading_state_spex` | samples every 15ms; asserts the ORDER the states appeared in |
| `61_search_streaming_spex` | 250 files; results on screen while the status still says "searching…" |

All five green against the pin. Every new assertion was verified by breaking
the code and watching it fail — that is not decoration, it caught two spex that
would have passed regardless.

**A loading state and a streaming search can only be tested by SAMPLING.** They
are states the pane passes through; a single look after the fact sees the end
of it and nothing else. Both spex poll every 10–15ms and assert on the sequence.

---

## Traps worth keeping

- **Do not `git checkout <file>` to undo a break-test.** It reverts the whole
  uncommitted file. This cost two reimplementations of work this session.
- **Do not `mix compile` (or anything that rebuilds) while a spex run is in
  flight.** It rebuilds the app underneath the run and kills it, leaving an
  orphaned `mix spex` holding port 9987 so nothing else can start.
- **Spex fixtures must not live under `test/support/`.** It is compiled into the
  test build, so a run interrupted before its `on_exit` leaves `.ex` files
  behind and `mix test` stops compiling entirely. All search fixtures now write
  to `System.tmp_dir!()`; this bit for real this session.
- `body_changed?` compares an input signature, never rebuilt rows. Do not put a
  `rows/1` call into a change check or a hover handler.
- Graph primitives are a **map**. There is no drawn order in `graph.primitives`
  — sort by the translate, or walk down from the group you mean.
- The pane and the find bar still share a **design but not code**. Five-plus
  fixes have now had to be made twice. A shared header component is the flagged
  refactor; still nobody has done it.

---

## The suite

Last full run against the pin: **168/185**, 17 failures, ~31 minutes. **None of
them are in search** — 41, 57, 58, 59 and 61 all pass.

The failing set churns badly between runs. Three full runs this session:

| | failures | notes |
|---|---|---|
| after step 1 | 13 | included "Find No Matches", not menu layout |
| after the bug fixes | 14 | word wrap appeared, "Find No Matches" passed |
| after steps 2 and 3 | 17 | +2 spex files added (183 → 185 tests) |

Every failure is outside search: word wrap, external file sync, scroll routing,
scrollbar drag, side-nav scroll, clipboard, folding, syntax-highlighting fonts,
discoverability, menu layout, saved settings, release visuals, and the demo.
**Treat the count as a signal, not a gate** — but do not read the churn as "all
flaky", because at least one of them is not:

- **`46_menu_layout_spex` fails reproducibly, alone, every time**: *"the view
  dropdown is 3px taller than the window; its last rows cannot be clicked."*
  Confirmed pre-existing by checking out `8e4c02d` (the commit before this
  session) and reproducing it identically. It is a real bug — the last rows of
  the View menu genuinely cannot be clicked — and it is worth fixing.
  It passed in two of this session's three full runs, so something about
  ordering or window size hides it. That is a second bug: a layout assertion
  that only sometimes notices.

- **`60_demo_spex`** used to die at the search section, clicking the
  replacement field without opening the disclosure it now lives behind. That is
  fixed and it now reaches much further, dying on the shortcut reference. Not
  investigated.

## Known, unfixed
- **ripgrep is not installed**, so every `Backend.Ripgrep` path — including the
  new `stream/3` — is unexercised. Installing rg is also the single biggest
  remaining win for search latency: it would put the whole search inside the
  debounce and make streaming moot.
- **2px overshoot at 130% zoom** (unchanged from last session).
- **The scope tree is capped at 12 rows** (`@scope_cap`), and the root node now
  takes one of them. A project with many top-level entries will truncate.

## Open question from the user, still unanswered

> "do we do syntax highlighting for markdown? We could do the same type of
> bold/italic/etc we did for code syntax"

Unchanged from last session: no markdown lexer in the dependency list, so this
is currently a "no". Somebody needs to check whether `makeup_markdown` exists
or whether it means writing a lexer.
