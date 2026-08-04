# Quillex 0.7.3 release handoff

## Public and architectural changes

- `Quillex.Buffer.Ref` is the stable identity passed across the public API;
  `Quillex.Buffer.Snapshot` is the immutable read contract.
- `Quillex.Buffer` owns new/open/list/activate/fetch/dispatch/close/save/reload.
  Saves and clipboard access are process-shell effects, never reducer effects.
- Runtime ownership is explicit through `:standalone`, `:embedded`, and
  `:headless`; the removed host-specific flag has no compatibility alias.
- Standalone native close is deferred to `Quillex.Lifecycle.Coordinator`.
- Pane scroll and fold state are view state and do not dirty a document.
- Release dependencies are immutable Git refs; `QUILLEX_LOCAL_DEPS=1` opts
  into the sibling-checkout development constellation.

Embedding callers should replace mutable/internal buffer structs with Ref and
Snapshot, configure `runtime_mode: :embedded`, and own their viewport and VM
lifetime. Flamelex's stale adapter is intentionally not revived here.

## Verification evidence

The implementation revisions are Quillex
`6da554a37d5a0cbb05cbc9903827489976e8d8a7`, Scenic
`bc2854bceb943e70247dcbe50167aff08cc7147e`, scenic_driver_local
`35de351b5bd2075e7651e9f8bef37e9f3659a85d`, and scenic-widget-contrib
`e0bc98d6b67025d3b9c052598a4c6584b1624a15`. Spex remains at
`fc1c21f74913c9d6899821b8265b1607c505b48b`.

The release was verified on Linux x86-64 with Elixir 1.18.4, Erlang/OTP 28.1,
and `SCENIC_LOCAL_TARGET=glfw`. Exact commands use the explicit local override:

```sh
QUILLEX_LOCAL_DEPS=1 SCENIC_LOCAL_TARGET=glfw MIX_ENV=test mix test
QUILLEX_LOCAL_DEPS=1 bash scripts/run_spex_quiet.sh
QUILLEX_LOCAL_DEPS=1 MIX_ENV=prod mix release --overwrite
```

Focused dependency evidence:

- Scenic nested-scissor regression: 1 test, 0 failures.
- scenic_driver_local close protocol: 2 tests, 0 failures.
- scenic-widget-contrib menu/modal/scroll/tab/folding/reducer matrix: 17 tests,
  0 failures.
- Spex repository suite: 44 tests, 0 failures.

The final performance scenario on this machine measured average GPU render
time 2.455 ms, maximum 3.583 ms, 46 sampled frames, zero slow frames, and
observed workload throughput 24.10 frames/s. These are a machine baseline, not a
portable guarantee. The editor keeps one TextField across buffer switches and
ordinary settings updates; layout rebuilds remain deliberate for z-order
changes.

The full Quillex suite passed 13 properties and 336 tests. Full Spex passed 117
tests with zero failures; its durable log is
`/tmp/spex_run_20260802_020221.log` and the empty JSONL failure artifact is
`/tmp/spex_run_20260802_020221.failures.jsonl`.

The assembled release is 102 MB at `_build/prod/rel/quillex`. A headless
release-node smoke test created a buffer, inserted `release-ok`, and read the
same text through the public Snapshot API. The distributable archive is
`/tmp/quillex-0.7.3-linux-x86_64.tar.gz`, SHA-256
`20c4bf5f8cda06d44bf95cfef8bfadc011a86780b90a4f0672cbc88b461dbeb6`.

## Visual captures

`26_release_visuals_spex.exs` generates baseline and material after-state
captures with `QUILLEX_CAPTURE_RELEASE=1`. Tracked framebuffer images live in
`docs/images/0.7.3/`, with matching rendered-text captures in
`docs/captures/0.7.3/`. They cover:

- baseline editor;
- typed View menu and live text-size slider;
- horizontally/vertically clipped SideNav;
- command-registry-generated shortcuts modal;
- clipped tab overflow;
- indentation folding;
- deferred dirty-close dialog.

## Limitations and preserved work

- The dependency result commits are local until their maintainers publish
  them; no remote branches or tags were mutated by this delivery.
- Native widget-repository window tests require a display server. The headless
  environment instead exercised component tests plus Quillex's GLFW semantic
  full-window Spex and framebuffer captures.
- Crash/session recovery and non-interactive OS-shutdown journaling remain
  separate post-0.7.3 work; graceful native-window close is protected.
- Existing compiler/Boundary warnings predate this release unless explicitly
  listed in the audit disposition.
- Pre-existing dirty and untracked work in every constellation repository was
  preserved and excluded from release commits.
