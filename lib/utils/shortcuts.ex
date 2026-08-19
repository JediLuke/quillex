defmodule Quillex.Shortcuts do
  @moduledoc """
  One spelling of every shortcut, printed the way this machine's keyboard works.

  ## The problem

  `Ctrl+S` is wrong on a Mac, where it is Command+S. So a
  menu that says "Save (Ctrl+S)" is telling a Mac user to press a key that
  does nothing, and the shortcut reference is a page of the same lie repeated
  forty times.

  Fixing that by writing both — "Ctrl+S / Cmd+S" — doubles the width of every
  menu to tell each person one thing they need and one they don't.

  ## The answer

  `Quillex.Commands` spells shortcuts canonically, with `Mod` standing for
  whichever key this person's keyboard calls the command key:

      shortcut: "Mod+S"

  `render/1` turns that into `Ctrl+S` or `Cmd+S` at the moment it is drawn. Since
  it is read from the setting each time, changing the setting changes every
  menu row and every line of the reference at once — there is no list of
  places to remember to update, because there is only one spelling.

  ## The Mac conventions, and the one this editor cannot keep

  Mac shortcuts are conventionally written as symbols with nothing between
  them — `⇧⌘S` — in a fixed order: Control, Option, Shift, Command. The order
  is not decoration; it is what every Mac menu has looked like for decades,
  and getting it backwards reads as foreign.

  The symbols are another matter. **IBM Plex Mono, which this editor draws its
  menus in, has no glyph for ⌘, ⇧, ⌥ or ⌃** — Scenic draws a missing glyph as
  an empty box, so a menu spelled the conventional way would read `▯▯S`. A
  wrong-looking shortcut is bad; an unreadable one is worse. So the modifiers
  are spelled as words, in the Mac order, with the separator that words need:
  `Shift+Cmd+S`.

  The keys themselves are a different story: Plex *does* have ← → ↑ ↓ ↖ ↘ ↩,
  so those are drawn as the symbols printed on the keys, which is both shorter
  and what a Mac user expects.

  If the menu font is ever replaced with one that covers U+2318 and its
  neighbours, this is the module to revisit — and `shortcuts_test.exs` says so
  where it asserts the words.

  ## The other half

  This module is what a person READS. What they PRESS is normalised on the way
  in by `normalize/1` — Command arrives from Scenic as `:meta` and becomes
  `:ctrl` before anything matches on it, so the key handling never learns
  there was a question. Both halves read the same setting, so they cannot
  drift apart.
  """

  alias Quillex.RadixCache.ViewStore

  @doc """
  The configured key: `:ctrl` (Control) or `:meta` (Command).

  Read from the view store, which is where the setting lives and where Save
  Settings as Default picks it up.
  """
  def primary_modifier, do: ViewStore.get_state().primary_modifier

  @doc """
  What this platform should default to, before anyone has said otherwise.

  macOS means Command; everything else means Control. This is a default and
  not a rule — see the setting in the View menu — because a Mac user with a
  Linux habit is a real person and should not have to fight the editor.
  """
  def default_primary_modifier do
    case :os.type() do
      {:unix, :darwin} -> :meta
      _ -> :ctrl
    end
  end

  @doc "The two choices, as `{id, label}`, for the menu that offers them."
  def choices do
    [
      {:ctrl, "Control (Ctrl)"},
      {:meta, "Command (Cmd)"}
    ]
  end

  @doc "The label for a modifier on its own, for a menu row."
  def label(modifier) do
    {^modifier, label} = Enum.find(choices(), fn {id, _} -> id == modifier end)
    label
  end

  # Control, Option, Shift, Command — the order every Mac menu prints them in.
  # Words rather than ⌃⌥⇧⌘ because the menu font has none of those four; see
  # the note above. Joined with "+", which words need and symbols would not.
  @mac_order [
    {"Ctrl", "Ctrl"},
    {"Alt", "Opt"},
    {"Shift", "Shift"},
    {"Mod", "Cmd"}
  ]

  # Named keys become the symbols printed on the keys — but only the ones the
  # menu font actually has. ⌫ (U+232B), ⌦, ⎋ and ⇥ are absent from IBM Plex
  # Mono just as the modifier symbols are, so those keep their names.
  @mac_keys %{
    "Left" => "←",
    "Right" => "→",
    "Up" => "↑",
    "Down" => "↓",
    "Home" => "↖",
    "End" => "↘",
    "Enter" => "↩"
  }

  @doc """
  A canonical shortcut, written for this keyboard.

      iex> Quillex.Shortcuts.render("Mod+Shift+S", :ctrl)
      "Ctrl+Shift+S"

      iex> Quillex.Shortcuts.render("Mod+Shift+S", :meta)
      "Shift+Cmd+S"

  Shortcuts with no `Mod` in them — Escape, F3 — come back unchanged on both.
  """
  def render(shortcut), do: render(shortcut, primary_modifier())

  def render(nil, _modifier), do: nil

  def render(shortcut, :ctrl) when is_binary(shortcut),
    do: String.replace(shortcut, "Mod", "Ctrl")

  def render(shortcut, :meta) when is_binary(shortcut) do
    parts = String.split(shortcut, "+")

    # The final part is the key itself; everything before it is a modifier.
    # Splitting on "+" this way also handles "Mod++" (zoom in), whose key IS a
    # plus sign, because the last element is then the empty string and the
    # symbol we want is the separator that produced it.
    {mods, [key]} = Enum.split(parts, -1)
    key = if key == "", do: "+", else: key

    @mac_order
    |> Enum.filter(fn {name, _printed} -> name in mods end)
    |> Enum.map(fn {_name, printed} -> printed end)
    |> Kernel.++([mac_key(key)])
    |> Enum.join("+")
  end

  defp mac_key(key), do: Map.get(@mac_keys, key, key)

  @doc """
  Rewrite a modifier list from Scenic so the configured key reads as `:ctrl`.

  Delegated to the widget library, which needs the same answer for the text
  fields it owns and cannot depend on this application to get it. The setting
  is pushed there by `apply/1` whenever it changes, so there is one setting
  with two readers rather than two settings that have to agree.
  """
  defdelegate normalize(mods), to: ScenicWidgets.PrimaryModifier

  @doc "As `normalize/1`, against a stated modifier rather than the setting."
  defdelegate normalize(mods, modifier), to: ScenicWidgets.PrimaryModifier

  @doc """
  Tell the widget library which key it is. Called at boot and on every change.
  """
  def apply(modifier) when modifier in [:ctrl, :meta] do
    ScenicWidgets.PrimaryModifier.put(modifier)
  end
end
