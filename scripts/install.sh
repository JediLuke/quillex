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
# Quillex builds against a constellation of forks, checked out beside it.
# Standalone clones aren't supported yet — that waits on the forks being
# tagged, after which mix.exs can name the tags directly.
bold "3. Checking the sibling forks"
missing=()
for sibling in scenic scenic_driver_local scenic-widget-contrib spex; do
  [ -d "$project_dir/../$sibling" ] || missing+=("$sibling")
done

if [ ${#missing[@]} -eq 0 ]; then
  note "all four present"
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
bold "5. The qlx command"
target="$HOME/.local/bin/qlx"
if [ -e "$target" ] || [ -L "$target" ]; then
  note "$target already exists — leaving it alone"
elif confirm "symlink bin/qlx to $target?"; then
  mkdir -p "$(dirname "$target")"
  ln -s "$project_dir/bin/qlx" "$target"
  note "linked $target"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) note "note: $HOME/.local/bin isn't on your PATH yet" ;;
  esac
else
  note "skipped — run it as $project_dir/bin/qlx, or link it later"
fi

bold "Done."
note "qlx .            open the current directory"
note "iex -S mix       a shell with the editor running"
note "scripts/run_spex_quiet.sh   the spex suite"
