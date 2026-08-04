#!/usr/bin/env bash
# install.sh — get Quillex building from source.
#
# This is the CONTRIBUTOR path: it assumes you want to hack on Quillex, and it
# needs Elixir, a C toolchain and OpenGL headers. It is not how you would hand
# the editor to someone who just wants to edit a file — see DISTRIBUTION.md.
#
#   scripts/install.sh            walk through it, asking before anything
#   scripts/install.sh --yes      assume yes (CI, or you've read it already)
#   scripts/install.sh --help
#
# What it does, in order:
#   1. checks Elixir and Erlang are present
#   2. installs GLFW, GLEW, pkg-config and a C compiler via your package manager
#   3. checks the sibling forks Quillex builds against are checked out
#   4. fetches and compiles everything
#   5. offers to put `qlx` on your PATH
set -euo pipefail

assume_yes=false
for arg in "$@"; do
  case "$arg" in
    -y | --yes) assume_yes=true ;;
    -h | --help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: unknown option $arg" >&2
      exit 64
      ;;
  esac
done

project_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '  %s\n' "$1"; }
die() {
  printf '\n\033[31minstall.sh: %s\033[0m\n' "$1" >&2
  exit 1
}

confirm() {
  $assume_yes && return 0
  # Ask on the terminal, not stdin — stdin may be a pipe (curl | bash).
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    die "need a terminal to ask '$1' — re-run with --yes if you're sure"
  fi
  printf '  %s [Y/n] ' "$1" > /dev/tty
  read -r reply < /dev/tty
  case "$reply" in
    [Nn]*) return 1 ;;
    *) return 0 ;;
  esac
}

# ── 1. Elixir ───────────────────────────────────────────────────────────────
# Deliberately not installed for you: a language runtime is your business, and
# which manager owns it (asdf, mise, brew, distro) is a decision with
# consequences beyond this repo.
bold "1. Checking Elixir"
if ! command -v mix > /dev/null 2>&1; then
  cat >&2 <<'EOF'
  No `mix` on PATH.

  Quillex needs Elixir 1.15+ and Erlang/OTP 26+. Either install them, or if
  you use a version manager, make sure its shims are on PATH — asdf's live in
  ~/.asdf/shims and are only added by a line in your shell profile.

      asdf:  https://asdf-vm.com/guide/getting-started.html
      mise:  https://mise.jdx.dev/getting-started.html
      or your distro's elixir/erlang packages

EOF
  die "Elixir is required"
fi
note "$(elixir --version | tr '\n' ' ' | sed 's/  */ /g')"

# ── 2. System libraries ─────────────────────────────────────────────────────
# Scenic renders through a C program that links GLFW and GLEW. Without their
# development headers the driver won't build; without the runtime libraries it
# won't start. See DISTRIBUTION.md §1.
bold "2. Checking system libraries (GLFW, GLEW)"

have_libs() { pkg-config --exists glfw3 glew 2> /dev/null; }

if command -v pkg-config > /dev/null 2>&1 && have_libs; then
  note "already present: glfw3 $(pkg-config --modversion glfw3), glew $(pkg-config --modversion glew)"
else
  os="$(uname -s)"
  if [ "$os" = Darwin ]; then
    command -v brew > /dev/null 2>&1 || die "Homebrew is required on macOS — see https://brew.sh"
    installer="brew install glfw glew pkg-config"
    sudo_needed=false
  elif command -v apt-get > /dev/null 2>&1; then
    installer="apt-get install -y build-essential pkg-config libglfw3-dev libglew-dev"
    sudo_needed=true
  elif command -v dnf > /dev/null 2>&1; then
    installer="dnf install -y gcc gcc-c++ make pkgconf-pkg-config glfw-devel glew-devel"
    sudo_needed=true
  elif command -v pacman > /dev/null 2>&1; then
    installer="pacman -S --needed --noconfirm base-devel glfw glew"
    sudo_needed=true
  elif command -v zypper > /dev/null 2>&1; then
    installer="zypper install -y gcc make pkg-config glfw-devel glew-devel"
    sudo_needed=true
  else
    die "couldn't identify your package manager — install GLFW3 + GLEW development packages and pkg-config by hand, then re-run"
  fi

  if [ "$sudo_needed" = true ] && [ "$(id -u)" -ne 0 ]; then
    command -v sudo > /dev/null 2>&1 || die "need root to install packages, and there's no sudo"
    installer="sudo $installer"
  fi

  note "this will run:"
  note "    $installer"
  confirm "install them?" || die "declined — install GLFW3 and GLEW yourself, then re-run"
  $installer

  have_libs || die "GLFW/GLEW still not visible to pkg-config after installing — something is off"
  note "installed: glfw3 $(pkg-config --modversion glfw3), glew $(pkg-config --modversion glew)"
fi

# SCENIC_LOCAL_TARGET does not need setting: scenic_driver_local's compiler
# task picks glfw on a desktop and cairo-fb on a framebuffer device by itself.

# ── 3. The sibling forks ────────────────────────────────────────────────────
# Only relevant when developing across the constellation. By default mix.exs
# fetches each fork from GitHub at a pinned revision, so a lone clone of
# quillex is all anyone needs — there is nothing to check here.
bold "3. Checking the sibling forks"

if [ "${QUILLEX_LOCAL_DEPS:-}" != 1 ] && [ "${QUILLEX_LOCAL_DEPS:-}" != true ]; then
  note "not needed — mix.exs fetches the forks from GitHub at pinned revisions"
  note "(developing across repos? export QUILLEX_LOCAL_DEPS=1 to build against"
  note " sibling checkouts instead, and re-run this to have them checked)"
  skip_siblings=true
else
  skip_siblings=false
fi

missing=()
if [ "$skip_siblings" = false ]; then
  for sibling in scenic scenic_driver_local scenic-widget-contrib spex; do
    [ -d "$project_dir/../$sibling" ] || missing+=("$sibling")
  done
fi

if [ "$skip_siblings" = true ]; then
  :
elif [ ${#missing[@]} -eq 0 ]; then
  note "all four present"

  # Present is not the same as correct. A plain `git clone` of these forks
  # checks out their DEFAULT branch — master for scenic and
  # scenic-widget-contrib — and the work Quillex needs lives elsewhere. The
  # build then succeeds against stale code and the editor comes up subtly
  # wrong: placeholder letters instead of toolbar icons, menus missing items.
  # Nothing errors, so it reads as "installed fine".
  #
  # mix.exs already names the exact revision each fork must contain, so use
  # that as the truth rather than a branch name that could drift.
  pinned_sha_for() { grep -A4 -F "\"../$1\"" mix.exs | grep -oE '[0-9a-f]{40}' | head -1; }

  expected_branch_for() {
    case "$1" in
      scenic) echo main ;;
      scenic_driver_local) echo main ;;
      scenic-widget-contrib) echo nice_module_attributes ;;
      spex) echo feature/context-struct-and-function-givens ;;
    esac
  }

  stale=()
  for sibling in scenic scenic_driver_local scenic-widget-contrib spex; do
    sha="$(pinned_sha_for "$sibling")"
    [ -n "$sha" ] || continue
    repo="$project_dir/../$sibling"

    if ! git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
      note "$sibling is not a git checkout — skipping revision check"
    elif ! git -C "$repo" cat-file -e "$sha^{commit}" 2> /dev/null; then
      stale+=("$sibling (revision not fetched yet)")
    elif ! git -C "$repo" merge-base --is-ancestor "$sha" HEAD 2> /dev/null; then
      stale+=("$sibling (on $(git -C "$repo" rev-parse --abbrev-ref HEAD), missing ${sha:0:8})")
    fi
  done

  if [ ${#stale[@]} -eq 0 ]; then
    note "all four contain the revisions mix.exs pins"
  else
    printf '\n'
    note "these forks do NOT contain the revision Quillex needs:"
    for s in "${stale[@]}"; do note "    $s"; done
    printf '\n'
    note "Quillex builds against these directories directly, so it would compile"
    note "against the wrong code. Fix with:"
    printf '\n'
    for sibling in scenic scenic_driver_local scenic-widget-contrib spex; do
      for s in "${stale[@]}"; do
        case "$s" in
          "$sibling "*)
            note "    git -C ../$sibling fetch origin && git -C ../$sibling checkout $(expected_branch_for "$sibling")"
            ;;
        esac
      done
    done
    printf '\n'
    confirm "continue anyway?" || die "stopped — check those out, then re-run"
  fi
else
  cat >&2 <<EOF

  Missing beside this checkout: ${missing[*]}

  Quillex currently builds against local forks, which must sit as siblings
  of the quillex directory:

      $(dirname "$project_dir")/
        quillex/
        scenic/                 github.com/JediLuke/scenic          (widget-v2)
        scenic_driver_local/    github.com/JediLuke/scenic_driver_local
        scenic-widget-contrib/  github.com/JediLuke/scenic-widget-contrib
        spex/                   github.com/JediLuke/spex

  Clone the missing ones there and re-run. Cloning a lone quillex repo will
  be supported once those forks are tagged.

EOF
  die "sibling forks required"
fi

# ── 4. Build ────────────────────────────────────────────────────────────────
bold "4. Fetching and compiling"
note "this takes a few minutes the first time (the C driver included)"
mix deps.get
mix compile

# ── 5. The qlx command ──────────────────────────────────────────────────────
# Re-running this step has to be safe and has to be honest. "Already exists"
# is not good enough: a symlink left over from a checkout you have since moved
# or deleted points somewhere wrong, and reporting that as done sends you off
# to debug a `qlx` that runs the wrong tree or nothing at all. So distinguish
# the cases, and only ever offer to replace a link this script could have made.
bold "5. The qlx command"

bin_dir="${QLX_BIN_DIR:-$HOME/.local/bin}"
target="$bin_dir/qlx"
source_cmd="$project_dir/bin/qlx"

link_it() {
  mkdir -p "$bin_dir"
  ln -sfn "$source_cmd" "$target"
  note "linked $target -> $source_cmd"
}

path_advice() {
  case ":$PATH:" in
    *":$bin_dir:"*)
      note "$bin_dir is on your PATH"
      return
      ;;
  esac

  # Name the file the user's own shell actually reads. macOS defaults to zsh,
  # most Linux distros to bash, and telling someone to edit the wrong one is
  # how "I followed the instructions and it still doesn't work" happens.
  case "$(basename "${SHELL:-}")" in
    zsh) profile="~/.zshrc" ;;
    bash) [ "$(uname -s)" = Darwin ] && profile="~/.bash_profile" || profile="~/.bashrc" ;;
    fish) profile="~/.config/fish/config.fish" ;;
    *) profile="your shell profile" ;;
  esac

  note "$bin_dir is NOT on your PATH yet — add this to $profile:"
  if [ "$(basename "${SHELL:-}")" = fish ]; then
    note "    fish_add_path $bin_dir"
  else
    note "    export PATH=\"$bin_dir:\$PATH\""
  fi
  note "then open a new shell, or run: export PATH=\"$bin_dir:\$PATH\""
}

if [ -L "$target" ]; then
  current="$(readlink "$target")"

  if [ "$current" = "$source_cmd" ]; then
    note "already linked to this checkout — nothing to do"
  elif [ ! -e "$target" ]; then
    note "$target is a broken symlink (points at $current)"
    if confirm "repoint it at this checkout?"; then
      link_it
    else
      note "left alone — qlx will not work until that is fixed"
    fi
  else
    note "$target already points at a different checkout:"
    note "    $current"
    if confirm "repoint it at $project_dir?"; then
      link_it
    else
      note "left alone — qlx will keep running the other checkout"
    fi
  fi
elif [ -e "$target" ]; then
  # A real file, not our symlink. Never clobber something we did not create.
  note "$target exists and is not a symlink — leaving it alone"
  note "remove it yourself if you want qlx linked here"
elif confirm "install the qlx shortcut into $bin_dir?"; then
  link_it
else
  note "skipped — run it as $source_cmd, or re-run this script later"
fi

[ -L "$target" ] && path_advice

bold "Done."
note "qlx .            open the current directory"
note "iex -S mix       a shell with the editor running"
note "scripts/run_spex_quiet.sh   the spex suite"
