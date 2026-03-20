# QuillEx

A simple text editor (basically a [Gedit](https://wiki.gnome.org/Apps/Gedit) clone) written entirely in Elixir, powered by the [Scenic](https://github.com/ScenicFramework/scenic) GUI framework.

![QuillEx demo](assets/demo.gif)

## Quick Start

```bash
git clone https://github.com/JediLuke/quillex.git
cd quillex
sh ./script/install.sh
iex -S mix
```

The install script detects your OS and installs the required system
dependencies (GLFW, GLEW, pkg-config), sets `SCENIC_LOCAL_TARGET=glfw`,
then fetches and compiles everything.

## Requirements

- **Elixir** 1.15+ and **Erlang/OTP** 26+
- **Git**
- **macOS**: [Homebrew](https://brew.sh)
- **Linux**: `gcc`, `make`, and a package manager

## Manual Setup & Troubleshooting

If the install script doesn't work for your system, or you run into issues,
see [docs/MANUAL_INSTALL.md](docs/MANUAL_INSTALL.md).

## License

See [LICENSE](LICENSE) for details.
