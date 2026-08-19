defmodule Quillex.ShortcutsTest do
  @moduledoc """
  What a shortcut looks like on each platform, and what a keystroke turns into.

  These are the two halves of one setting — printed and pressed — and the thing
  that would actually hurt is them disagreeing: a menu that says ⌘S over a
  handler that only answers to Control.
  """
  use ExUnit.Case, async: true

  alias Quillex.Shortcuts

  describe "printing a shortcut" do
    test "on a Control keyboard, Mod is simply Ctrl" do
      assert Shortcuts.render("Mod+S", :ctrl) == "Ctrl+S"
      assert Shortcuts.render("Mod+Shift+S", :ctrl) == "Ctrl+Shift+S"
      assert Shortcuts.render("Mod+Alt+[", :ctrl) == "Ctrl+Alt+["
    end

    test "on a Mac, the Mac's names for the keys" do
      assert Shortcuts.render("Mod+S", :meta) == "Cmd+S"
      assert Shortcuts.render("Mod+Shift+S", :meta) == "Shift+Cmd+S"
    end

    test "and in the order every Mac menu prints them: Control, Option, Shift, Command" do
      # Not decoration — a menu ordering these the other way round reads as
      # foreign to the person it is for.
      assert Shortcuts.render("Mod+Alt+[", :meta) == "Opt+Cmd+["
      assert Shortcuts.render("Mod+Shift+Z", :meta) == "Shift+Cmd+Z"
    end

    test "spelled as words, because the menu font has no ⌘, ⇧, ⌥ or ⌃" do
      # IBM Plex Mono covers none of U+2318, U+21E7, U+2325, U+2303, and
      # Scenic draws a missing glyph as an empty box — so the conventional
      # ⇧⌘S would reach the screen as ▯▯S. Words are less native and far more
      # legible than that.
      #
      # If the menu font is ever replaced with one that covers them, this is
      # the test that should be changed on purpose rather than discovered.
      for shortcut <- ["Mod+S", "Mod+Shift+S", "Mod+Alt+[" ] do
        rendered = Shortcuts.render(shortcut, :meta)

        for glyph <- ["⌘", "⇧", "⌥", "⌃", "⌫", "⌦", "⎋", "⇥"] do
          refute String.contains?(rendered, glyph),
                 "#{rendered} uses #{glyph}, which the menu font cannot draw"
        end
      end
    end

    test "but arrow keys DO become symbols, because those the font has" do
      assert Shortcuts.render("Mod+Left", :meta) == "Cmd+←"
      assert Shortcuts.render("Mod+Home", :meta) == "Cmd+↖"

      # Backspace has no glyph in this font, so it keeps its name.
      assert Shortcuts.render("Mod+Backspace", :meta) == "Cmd+Backspace"
    end

    test "a shortcut whose key IS a plus survives the split" do
      # "Mod++" splits into ["Mod", "", ""] — the key is the separator that
      # produced the empty tail, and a naive split loses it.
      assert Shortcuts.render("Mod++", :ctrl) == "Ctrl++"
      assert Shortcuts.render("Mod++", :meta) == "Cmd++"
    end

    test "shortcuts with no modifier are the same on both" do
      assert Shortcuts.render("F3", :ctrl) == "F3"
      assert Shortcuts.render("F3", :meta) == "F3"
    end

    test "no shortcut renders as no shortcut" do
      assert Shortcuts.render(nil, :ctrl) == nil
    end
  end

  describe "pressing a shortcut" do
    test "on a Control keyboard, nothing is rewritten" do
      assert Shortcuts.normalize([:ctrl], :ctrl) == [:ctrl]
      assert Shortcuts.normalize([:ctrl, :shift], :ctrl) == [:ctrl, :shift]
    end

    test "on a Mac, Command reads as ctrl so every existing clause still matches" do
      assert Shortcuts.normalize([:meta], :meta) == [:ctrl]
      assert Shortcuts.normalize([:meta, :shift], :meta) == [:ctrl, :shift]
    end

    test "and Control on a Mac means nothing, because it is not the command key" do
      # Ctrl+S on a Mac should not save. Were this to leak through, every
      # shortcut would fire on two different keys.
      assert Shortcuts.normalize([:ctrl], :meta) == []
    end

    test "keys that are not modifiers pass through untouched" do
      assert Shortcuts.normalize([:shift], :meta) == [:shift]
      assert Shortcuts.normalize([], :meta) == []
    end
  end

  describe "the two halves agree" do
    test "every shortcut in the registry is spelled canonically" do
      # A "Ctrl+" left in the registry would print as Ctrl on a Mac while the
      # handler answered to Command — the exact disagreement this is for.
      offenders =
        Quillex.Commands.all()
        |> Enum.filter(&(&1.shortcut && String.contains?(&1.shortcut, "Ctrl")))
        |> Enum.map(& &1.id)

      assert offenders == [], "these should say Mod, not Ctrl: #{inspect(offenders)}"
    end

    test "every registry shortcut renders on both platforms" do
      for command <- Quillex.Commands.all(), command.shortcut do
        for modifier <- [:ctrl, :meta] do
          rendered = Shortcuts.render(command.shortcut, modifier)

          assert is_binary(rendered) and rendered != "",
                 "#{command.id} rendered as #{inspect(rendered)} on #{modifier}"
        end
      end
    end
  end

  describe "the default" do
    test "is the platform's, and is one of the two" do
      assert Shortcuts.default_primary_modifier() in [:ctrl, :meta]
    end

    test "and it is a saved setting, so a chosen one survives the session" do
      assert :primary_modifier in Quillex.SettingsFile.persisted_keys()
    end
  end
end
