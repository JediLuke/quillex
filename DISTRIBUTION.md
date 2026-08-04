# Distributing Quillex

How Quillex gets onto a machine that isn't a developer's. Written after
spiking the options; the measurements here are from an actual build, not
from documentation.

**Status:** `mix release` works and `bin/qlx` runs it. Nothing is packaged for
end users yet. Burrito was tried and rejected — see [Roads not
taken](#roads-not-taken).

---

## 1. What Quillex actually needs at runtime

Everything downstream follows from this table, so it comes first. Measured
against `_build/prod/rel/quillex` on Pop!\_OS, x86_64, OTP 28.1 / ERTS 16.1.

The release is **93 MB**, of which **57 MB is the bundled Erlang runtime**. It
carries its own ERTS, so the target machine needs no Elixir and no Erlang. It
is *not* otherwise self-contained:

| Needs on the target | Where from | Risk |
|---|---|---|
| `libglfw.so.3`, `libGLEW.so.2.2` | the Scenic driver | **Not on a stock desktop.** Must be installed. |
| `libcrypto.so.3` (OpenSSL 3.x) | Erlang's `crypto` NIF | Breaks on anything still on OpenSSL 1.1 |
| `libGL`, `libGLX`, `libGLdispatch`, `libX11` | the Scenic driver | Fine — always present on a desktop, and you *want* the host's, since GL drivers are hardware-specific |
| `libc`, `libstdc++`, `libgcc_s`, `libtinfo`, `libz` | ERTS | Fine, but glibc is **forward-only**: built here, won't run on an older distro |

### The fact that drives everything: the renderer is a separate program

Scenic does not draw from inside the BEAM. `scenic_driver_local` builds a
standalone ELF executable and Scenic spawns it as a port:

```elixir
# scenic_driver_local/lib/driver.ex:256
port = Port.open({:spawn, executable}, [:binary, {:packet, 4}])
```

That executable has **15 dynamic dependencies**, including GLFW and GLEW. It
is built by `elixir_make` from a Makefile that is frankly platform-bound:

```make
LDFLAGS += `pkg-config --static --libs glfw3 glew`
ifeq ($(shell uname),Darwin)
    LDFLAGS += -framework Cocoa -framework OpenGL
```

Three consequences, and they shape every option below:

1. **It is not a NIF.** Packaging tools that talk about "handling NIFs" are
   talking about shared objects loaded into the BEAM. This is a child process
   with its own executable bit, which is a different problem — and a less
   well-trodden one.
2. **Cross-compilation is off the table.** Building the macOS binary from
   Linux means Cocoa and OpenGL frameworks. No amount of clever C-compiler
   substitution conjures those. **Build on each platform you ship to.**
3. **"Single binary" can never mean "no dependencies"** while the GUI links
   system GL libraries. Anything claiming otherwise has to *bundle* those
   libraries, not eliminate them.

---

## 2. Where we are now

`mix release` produces `_build/prod/rel/quillex` — app, deps and ERTS in one
directory, no Mix and no source tree behind it. `bin/qlx` runs it and offers
to build it if it's missing. See the README for the user-facing side.

Two things worth keeping when this gets packaged:

- **`rel/env.sh.eex` sets `RELEASE_DISTRIBUTION=none`.** Mix releases enable
  distribution by default so `bin/quillex remote` works; that starts epmd,
  which listens on 4369 for as long as the editor is open. With it off, the
  running editor holds **zero listening sockets** (verified with `lsof -p
  <pid> -a -i`: no inet file descriptors at all). A text editor should not be
  holding a port. Keep this property.
- **`bin/qlx`'s launcher logic is reusable.** Adopting the shell's working
  directory, resolving the target path, detaching into its own session — an
  AppImage `AppRun` and a macOS `Contents/MacOS` stub both need exactly that.
  Don't rewrite it three times.

A tarball of this release runs on "a distro roughly as new as the build
machine, after `apt install libglfw3 libglew2.2`". Fine for the power-user
option. Not a download-and-run experience.

---

## 3. Linux: AppImage

**Recommended first target.** One file, no root, no package manager, works
across distros.

The reasoning: AppImage is the only Linux format that solves the GLFW/GLEW
problem *for* the user. It bundles those libraries inside the image while
letting the host supply `libGL`/`libX11` — which is what you want anyway,
because GL drivers belong to the hardware. It also drops the glibc floor if
you build the image inside an older base (Ubuntu 22.04), which a plain tarball
built on your laptop can't do.

Sketch:

```
Quillex.AppDir/
  AppRun                 <- bin/qlx's launcher logic, minus the build step
  quillex.desktop        <- MIME associations => "Open With" in the file manager
  quillex.png
  usr/
    lib/                 <- bundled libglfw, libGLEW, libcrypto
    rel/                 <- the mix release, verbatim
```

Then `appimagetool Quillex.AppDir`. Exclude `libGL*` and `libX11*` from the
bundle deliberately — bundling those is the classic way to make an AppImage
that fails on somebody else's GPU.

You get the `.desktop` file and MIME associations by convention, so Quillex
shows up in the launcher and in "Open With" for text files.

**Corroboration:** ElixirKit's own guidance for Linux is per-distribution
builds or AppImage, because their Linux builds — unlike their macOS and
Windows ones — don't statically link OpenSSL. The Livebook team hit this same
wall.

---

## 4. macOS: the whole hog

The goal is a real citizen of the platform: dock icon, menu bar, double-click
a `.txt` and it opens in Quillex, drag a file onto the icon and it opens.
Gatekeeper silent.

Good news first: **Tauri is not needed and would actively hurt.** More on that
in [Roads not taken](#roads-not-taken). Scenic already opens a native
NSWindow through GLFW, so a `.app` bundle is mostly *layout plus metadata*.

### 4.1 The bundle

```
Quillex.app/
  Contents/
    Info.plist
    MacOS/quillex          <- launcher stub (see 4.3)
    Resources/
      quillex.icns
      rel/                 <- the mix release, built ON macOS
```

`Info.plist` keys that matter:

| Key | Why |
|---|---|
| `CFBundleIdentifier` | e.g. `gallery.gofish.quillex`. Identity for codesigning, preferences, and Launch Services. Pick it once, never change it. |
| `NSHighResolutionCapable` = `true` | **Without this the whole editor renders blurry on Retina.** Easy to miss, very visible. |
| `CFBundleDocumentTypes` | The "Open With" list. Entries with `LSItemContentTypes` of `public.plain-text`, `public.source-code`, plus `CFBundleTypeRole = Editor`. |
| `LSHandlerRank` | `Alternate` unless you want to fight TextEdit for the default. |
| `CFBundleIconFile`, `CFBundleShortVersionString`, `LSMinimumSystemVersion` | Ordinary bundle hygiene. |

### 4.2 The trap: macOS does not use argv for "Open With"

This is the single most important thing on this page for macOS, and it is
where the work actually is.

`qlx notes.txt` passes a path in `argv`. **Finder does not.** Double-clicking a
document, or dropping it on the dock icon, sends an **Apple Event**
(`kAEOpenDocuments`) to the running application. An app that only reads `argv`
opens an empty buffer and looks broken.

Handling that needs native code in the `NSApplication` delegate. Two open
questions to settle before committing to a design — **both need verifying, I
have not confirmed either**:

1. Does GLFW's Cocoa backend already install an application delegate that
   swallows or forwards `application:openFiles:`? GLFW does install its own
   delegate, so a second one may conflict.
2. Can a delegate be installed *around* GLFW's without the two fighting over
   `NSApp.delegate`?

**This is exactly where ElixirKit's native side earns its place — without
Tauri.** Its whole job is running an Elixir release from a native host process
and passing messages between them. Using it purely as the Apple-Event bridge,
and letting Scenic keep the window, is a legitimate and much smaller use of it
than what Livebook does.

### 4.3 The launcher stub, and single-instance

Related, and cross-platform: `qlx` currently starts a **fresh instance every
time**. On macOS that's not merely untidy, it's wrong — the platform
convention is that the running app receives the open request and shows a new
tab. Same for a second `qlx` on Linux.

That wants:

- a **single-instance check** on startup, and
- an **IPC channel** into the running BEAM to say "open this path".

`scenic_mcp`'s TCP server is the dev-mode precedent for that channel, but it's
a dev dependency and it listens on a TCP port, which section 2 is at pains to
avoid. A **unix-domain socket** in the release is the right shape: no port, no
network exposure, filesystem permissions do the access control.

Worth designing once and using on both platforms.

### 4.4 Codesigning and notarization

Without this, users get *"Quillex cannot be opened because the developer
cannot be verified"* and most will stop there.

- **Apple Developer Program**, $99/year, for a Developer ID Application
  certificate. No way around it for distribution outside the App Store.
- **Sign inside-out.** The release contains many `.so`/`.dylib` files *and* the
  `scenic_driver_local` executable. Every Mach-O gets signed, innermost first,
  then the bundle.
- **Hardened runtime is required for notarization**, and here is the Erlang
  gotcha: OTP 24+ ships **BeamAsm, a JIT**. Hardened runtime blocks
  writable-executable memory by default, so expect to need
  `com.apple.security.cs.allow-jit` and possibly
  `com.apple.security.cs.allow-unsigned-executable-memory` in the
  entitlements. *Unverified — test early, because it fails at runtime rather
  than at signing time.*
- **Notarize** with `notarytool submit --wait`, then `stapler staple` so the
  ticket travels offline with the app.
- `ElixirKit.Release.codesign/1` exists and does this for Elixir releases.
  Worth reading even if the rest of ElixirKit isn't used.

### 4.5 OpenSSL on macOS

Section 1 flagged `libcrypto` on Linux. On macOS it's worse: macOS ships no
usable OpenSSL, so an asdf- or Homebrew-built Erlang links `crypto` against
`/opt/homebrew/lib/libcrypto.dylib` — **a path that does not exist on a user's
Mac.**

Options: build ERTS against a static OpenSSL, or bundle the dylibs into
`Contents/Frameworks` and rewrite the install names with `install_name_tool`.
ElixirKit statically links OpenSSL for exactly this reason.

Check whether Quillex needs `crypto` at all first — if nothing pulls it in at
runtime it may be droppable from the release, which makes this whole section
evaporate.

### 4.6 Architectures

ERTS is per-architecture. Apple Silicon and Intel need either two builds or a
`lipo`-merged universal bundle. Given Intel Macs are fading, arm64-only with
an honest note is a defensible start.

---

## 5. Windows

Sketch only, until someone asks for it. Scenic's window is native there too,
so the shape is the same: build on Windows, wrap the release in an installer
(Inno Setup / WiX), register file associations in the registry rather than an
`Info.plist`. ElixirKit statically links OpenSSL on Windows, so that problem is
smaller than on macOS.

---

## 6. Roads not taken

### Burrito — rejected

[Burrito](https://github.com/burrito-elixir/burrito) wraps a Mix release into a
single executable per platform, cross-compiling with Zig. It is a good tool.
It is a poor fit for Quillex, and the reason is Quillex's, not Burrito's.

What the spike established:

- Burrito 1.6.0 requires **Zig 0.16.0 exactly** — its README says 0.15.2,
  which is stale. Also needs `xz`, and `7z` for Windows targets.
- It adds only `burrito` and `typed_struct` as dependencies. Clean.
- **The release assembled fine.** Failure was purely the Zig version gate; the
  wrap step was never reached.

Why it was abandoned anyway, independent of the version gate:

- Its NIF machinery (`nif_cflags`, `skip_nifs`, elixir_make recompilation)
  targets shared objects. The Scenic driver is a spawned **executable**;
  whether the archiver preserves its executable bit is untested and
  undocumented.
- It removes the *Elixir* install requirement but not the *system library*
  one. Users would still need GLFW and GLEW.
- **Cross-compilation — its main selling point — can't work here**, per
  section 1. And once you're building on each platform anyway, Burrito's
  contribution shrinks to "one file instead of a directory", which AppImage
  and `.app` already give you, along with the OS integration they don't.

The spike has been fully reverted from `mix.exs` and `mix.lock`.

### ElixirKit + Tauri — not applicable

[ElixirKit's Tauri integration](https://elixirkit.hexdocs.pm/tauri.html) points
a **webview at `http://127.0.0.1:4000`**, where a Phoenix LiveView server
renders the UI; Rust handles windowing and installers, and the two sides talk
over a PubSub bridge.

That is the shape of the problem [Livebook
had](https://news.livebook.dev/introducing-the-livebook-desktop-app-4C8dpu): a
web app has no window, and Tauri gives it one.

**Quillex already has a window.** Adding Tauri yields either two windows on
screen — an empty webview plus Scenic's real one — or rewriting the entire
editor as LiveView HTML and discarding the Scenic renderer, which is the thing
that was built. Quillex isn't a worse fit than Livebook here; it is *past* the
problem this layer solves.

Two pieces of ElixirKit remain worth stealing, and are referenced above:
`ElixirKit.Release.codesign/1` (§4.4) and its native-host bridge as an
Apple-Event handler (§4.2).

### An "install Elixir and build from source" script — not distribution

Worth having, and the README currently promises one that doesn't exist (see
below). But it asks a stranger to install Elixir, Erlang, a C toolchain and GL
headers in order to open a text file. That's the **contributor** path. Don't
confuse the two.

---

## 7. Open items

Roughly in the order they should be picked up:

1. **The README is broken today.** Quick Start says `sh ./script/install.sh`
   and links `docs/MANUAL_INSTALL.md`; **neither file exists**. This is the
   path a curious developer takes right now, and it fails at step three.
   Cheaper to fix than anything else here, and more damaging while unfixed.
2. **AppImage for Linux** — the first real user-facing artifact.
3. **Single-instance + unix-socket IPC for file-open** (§4.3). Needed by
   macOS, wanted on Linux, and best designed once.
4. **Verify the Apple Event / GLFW delegate question** (§4.2) before
   committing to a macOS design. It decides whether ElixirKit is pulled in.
5. **Verify hardened-runtime JIT entitlements** (§4.4) early, since it fails
   at runtime rather than at signing time.
6. **Determine whether `crypto` is needed at runtime** (§4.5) — if not, a
   whole class of dylib pain disappears.

## 8. Housekeeping

`_build/prod/rel/quillex_burrito/` is a stale output directory left by the
spike. It's inert — `bin/qlx` and `mix release` both target
`_build/prod/rel/quillex` — but it can be deleted.
