# Repository Guidelines

## Project Structure & Module Organization
- `lib/` holds the application code, organized by domain (e.g., `gui/`, `buffers/`, `core/`, `utils/`).
- `test/` mirrors `lib/` with ExUnit tests plus support helpers in `test/support/` and `test/test_helpers/`.
- `assets/` contains static assets used by the Scenic UI.
- `config/` contains environment configuration; `mix.exs` defines app metadata and dependencies.
- `tools/` and `biblio/` store auxiliary scripts and notes; `_build/` and `deps/` are build artifacts.

## Build, Test, and Development Commands
- `mix deps.get` fetches dependencies (note: several are local path deps).
- `mix compile` compiles the project.
- `iex -S mix run` starts the app in dev mode (matches README guidance).
- `mix test` runs the full ExUnit suite.
- `mix format` formats `mix`, `config`, `lib`, and `test` sources per `.formatter.exs`.
- Spex runs require `SCENIC_LOCAL_TARGET=glfw` (cairo-gtk is currently broken for spex).
  Example: `SCENIC_LOCAL_TARGET=glfw MIX_ENV=test mix spex test/spex/quillex/01_app_launch_spex.exs`.

## Coding Style & Naming Conventions
- Elixir code uses standard `mix format` conventions; run it before committing.
- Indentation is two spaces (Elixir default).
- Module and file names follow Elixir conventions (e.g., `QuillEx.Foo` in `lib/foo.ex`).
- Test files use the `_test.exs` suffix and live under `test/`.

## Testing Guidelines
- The suite is ExUnit-based; property tests use StreamData in `test/property/`.
- Prefer small, focused tests near the relevant domain folder.
- Run `mix test` locally before opening a PR; add tests for bug fixes and core logic.

## Commit & Pull Request Guidelines
- Recent commit messages are short and informal (no strict convention observed). Keep them concise and descriptive.
- PRs should include: a brief summary, testing notes (`mix test` or scoped command), and screenshots for UI changes in Scenic.
- Link related issues or documents (e.g., `GEDIT_CLONE_ROADMAP.md`) when applicable.

## Local Dependencies & Setup Notes
- `mix.exs` uses local path dependencies for Scenic and related libraries; ensure sibling repos exist (e.g., `../scenic`, `../scenic_driver_local`).
- Scenic requires OpenGL system deps; follow the Scenic install docs before running.
