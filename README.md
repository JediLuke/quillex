# QuillEx

A simple text editor (basically a [Gedit](https://wiki.gnome.org/Apps/Gedit) clone) written entirely in Elixir, powered by the [Scenic](https://github.com/ScenicFramework/scenic) GUI framework.

![QuillEx demo](assets/demo.gif)

## Quick Start

### Prerequisites

- **Elixir** 1.12+ and **Erlang/OTP** 24+
- **Git**
- **macOS**: [Homebrew](https://brew.sh)
- **Linux**: `gcc`, `make`, and a package manager

### Install and Run

```bash
git clone https://github.com/JediLuke/quillex.git
cd quillex
./script/install
iex -S mix
```

The install script will:
1. Install system dependencies (GLFW, GLEW, pkg-config)
2. Set the `SCENIC_LOCAL_TARGET=glfw` environment variable
3. Fetch and compile all Elixir dependencies

### Manual Setup

If you prefer to set things up yourself:

**macOS:**
```bash
brew install glfw3 glew pkg-config
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y build-essential pkg-config libglfw3-dev libglew-dev libgl1-mesa-dev
```

**Fedora:**
```bash
sudo dnf install -y glfw glfw-devel pkgconf glew glew-devel
```

**Arch:**
```bash
sudo pacman -S --needed glfw-x11 glew pkg-config
```

Then set the Scenic driver target and build:

```bash
export SCENIC_LOCAL_TARGET=glfw  # add this to your .zshrc or .bashrc
mix deps.get
mix compile
iex -S mix
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+S` | Save |
| `Ctrl+O` | Open file |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Ctrl+F` | Find |
| `Ctrl+A` | Select all |
| `Ctrl+C` | Copy |
| `Ctrl+V` | Paste |
| `Ctrl+X` | Cut |

## Troubleshooting

### `cairo.h not found` or compiles with wrong driver

Make sure `SCENIC_LOCAL_TARGET=glfw` is set in your environment:

```bash
echo $SCENIC_LOCAL_TARGET  # should print "glfw"
```

If not, add `export SCENIC_LOCAL_TARGET=glfw` to your `~/.zshrc` or `~/.bashrc` and restart your terminal.

### `unknown application: :file_system`

Run `mix deps.update scenic_widget_contrib` to get the latest version.

### Dependency version conflicts

If you see "does not match the requirement" errors, try:

```bash
mix deps.clean --all
mix deps.get
```

## License

See [LICENSE](LICENSE) for details.
