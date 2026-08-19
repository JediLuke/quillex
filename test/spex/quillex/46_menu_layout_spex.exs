defmodule Quillex.MenuLayoutSpex do
  @moduledoc """
  Part II item 7: menubar polish.

  Two things a menu has to get right, and neither is visible from the code that
  builds it:

  1. **Grouping.** Rows that belong together sit together, separated from the
     rows that do not. The fold controls in particular used to sit alone at the
     bottom of View, after Zoom, so "Set Fold Level" read as an afterthought
     rather than the third member of a group.
  2. **Fit.** A dropdown is drawn at whatever height its rows add up to. Rows
     past the bottom of the window are not merely ugly — they cannot be
     clicked, so a feature that is *in* the menu is still unreachable. View has
     grown to five groups, and this is the assertion that keeps it honest.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp icon_menu_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :icon_menu)
    :sys.get_state(pid, 30_000).assigns.state
  end

  # The ids of a menu's rows, dividers included, in the order they are drawn.
  defp row_ids(menu_id) do
    icon_menu_state().menus
    |> Enum.find(&(&1.id == menu_id))
    |> Map.fetch!(:items)
    |> Enum.map(&ScenicWidgets.IconMenu.State.get_item_id/1)
  end

  # Rows between one divider and the next: what the eye reads as a group.
  defp groups(menu_id) do
    row_ids(menu_id)
    |> Enum.chunk_by(&String.contains?(&1, "_divider"))
    |> Enum.reject(fn chunk -> Enum.all?(chunk, &String.contains?(&1, "_divider")) end)
  end

  # Every string a component actually draws, from its live graph.
  defp drawn_text(child_id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, child_id)

    :sys.get_state(pid, 30_000).assigns.graph
    |> Scenic.Graph.reduce([], fn
      %Scenic.Primitive{module: Scenic.Primitive.Text, data: text}, acc -> [text | acc]
      _primitive, acc -> acc
    end)
  end

  defp group_containing(menu_id, row_id) do
    Enum.find(groups(menu_id), &(row_id in &1))
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    Process.sleep(300)
    :ok
  end

  spex "Menu rows are grouped by what they do",
    description: "Dividers separate jobs; the fold controls read as one group",
    tags: [:phase_46, :menubar] do
    scenario "reading the three menus' groupings" do
      then_ "folding is a group of its own, not a tail on the end of View", context do
        folding = group_containing(:view, "toggle_fold")

        assert folding == ["toggle_fold", "unfold_all", "fold_level"],
               "the fold controls should be one group, got #{inspect(folding)}"

        refute List.last(row_ids(:view)) == "fold_level",
               "folding should no longer be the last thing in the menu"

        {:ok, context}
      end

      then_ "View reads as panels, text, folding, sizes, theme, preferences, keys, defaults",
            context do
        assert [panels, text, folding, sizes, theme, preferences, keys, defaults] = groups(:view)

        assert panels == ["file_nav"]
        assert "line_numbers" in text and "word_wrap" in text
        assert folding == ["toggle_fold", "unfold_all", "fold_level"]
        assert sizes == ["text_size", "tab_width", "chrome_zoom"]
        assert hd(theme) == "theme_heading"
        assert preferences == ["action_feedback", "menu_shortcuts"]

        # Which key means "command" is a group of its own: it changes what is
        # printed on every other row in every menu, which is not something to
        # read as a third preference toggle.
        assert hd(keys) == "modifier_heading"

        # The rows in this menu that outlive the session get a group of their
        # own, so they cannot be read as more preference toggles.
        assert defaults == ["save_default_settings", "edit_search_excludes"]
        {:ok, context}
      end

      then_ "every theme is a row of its own under the Theme heading", context do
        theme_group = group_containing(:view, "theme_heading")

        for {id, _label} <- Quillex.GUI.Palette.themes() do
          assert "theme_#{id}" in theme_group
        end

        {:ok, context}
      end

      then_ "File separates opening, writing, reconciling with disk, and closing",
            context do
        assert [open, write, disk, close] = groups(:file)
        assert open == ["new", "open"]
        assert write == ["save", "save_as"]
        assert disk == ["verify", "reload"]
        assert close == ["close"]
        {:ok, context}
      end

      then_ "Edit separates history, clipboard, selection, find, project find, navigation",
            context do
        assert [history, clipboard, selection, find, project, navigate] = groups(:edit)
        assert history == ["undo", "redo"]
        assert clipboard == ["cut", "copy", "paste"]
        assert selection == ["select_all", "delete_line"]
        assert find == ["find", "find_replace", "find_next"]
        assert project == ["find_in_project", "replace_in_project"]
        assert navigate == ["goto_line"]
        {:ok, context}
      end
    end
  end

  spex "Every dropdown fits inside the window",
    description: "A row below the bottom edge cannot be clicked, so it may as well not exist",
    tags: [:phase_46, :menubar] do
    scenario "opening each menu and measuring it" do
      then_ "no dropdown, at any of its rows, reaches past the window", context do
        height = root_state().frame.size.height

        for {menu_id, bounds} <- icon_menu_state().dropdown_bounds do
          assert bounds.y + bounds.height <= height,
                 "the #{menu_id} dropdown is #{trunc(bounds.y + bounds.height - height)}px " <>
                   "taller than the window; its last rows cannot be clicked"

          for {row_id, row} <- bounds.items do
            assert row.y + row.height <= height,
                   "row #{row_id} of #{menu_id} falls below the window"
          end
        end

        {:ok, context}
      end

      then_ "the View menu still fits with the chrome scaled up", context do
        Quillex.RadixCache.ViewStore.set_chrome_zoom(130)
        Process.sleep(500)

        height = root_state().frame.size.height
        view = Map.fetch!(icon_menu_state().dropdown_bounds, :view)

        assert view.y + view.height <= height,
               "at 130% chrome zoom the View menu is #{trunc(view.y + view.height - height)}px " <>
                 "too tall"

        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "no menu label is truncated", context do
        # A truncated label is worse than a missing one: "Highlight Current…"
        # appeared twice in View, and "Alchemical Wedding…" twice under Theme,
        # so two pairs of rows were literally indistinguishable. The cause was
        # the dropdown being clamped to the width of the icon strip it hangs
        # from rather than to the window.
        #
        # "Truncated" cannot be spotted by looking for a trailing ellipsis —
        # "Open File…" and "Go to Line…" end in one by convention. What it
        # means is that the text DRAWN differs from the label in the model.
        Probes.click_element("icon_menu_view")
        Process.sleep(400)

        # Sliders, steppers and selects draw their label and their value as
        # separate strings, so only the plain rows can be compared this way —
        # and they are exactly the rows the bug affected.
        plain = [
          ScenicWidgets.Menu.Model.Item,
          ScenicWidgets.Menu.Model.Toggle,
          ScenicWidgets.Menu.Model.Radio
        ]

        expected =
          icon_menu_state().menus
          |> Enum.find(&(&1.id == :view))
          |> Map.fetch!(:items)
          |> Enum.filter(&(is_struct(&1) and &1.__struct__ in plain))
          |> Enum.map(&ScenicWidgets.IconMenu.State.display_label/1)
          |> Enum.reject(&(&1 in ["", nil]))

        drawn = drawn_text(:icon_menu)

        for label <- expected do
          assert label in drawn,
                 "the View menu draws #{inspect(label)} truncated"
        end

        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the View menu is legible on screen", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{name: "menu-layout.txt", data: ["one", "two", "three"]})

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(1_500)
        Probes.click_element("icon_menu_view")
        Process.sleep(1_500)
        Probes.take_screenshot("46_view_menu")
        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end
    end
  end
end
