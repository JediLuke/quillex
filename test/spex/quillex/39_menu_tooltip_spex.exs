defmodule Quillex.MenuTooltipSpex do
  @moduledoc "Exercises delayed, stationary-hover tooltips on the reusable icon menu."
  use SexySpex

  alias Quillex.TestHelpers.{AppReset, SemanticProbe}
  alias ScenicMcp.Probes

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    {:ok, %{}}
  end

  spex "Menu icons explain themselves after a stationary hover",
    description: "Tooltips wait before appearing and disappear as soon as the pointer moves away",
    tags: [:phase_39, :menu, :tooltip, :hover] do
    scenario "Hovering the File icon" do
      when_ "the pointer leaves before the delay expires", context do
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_file)
        Probes.send_mouse_move(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2)
        Process.sleep(250)
        Probes.send_mouse_move(10, 100)
        Process.sleep(450)
        {:ok, context}
      end

      then_ "the cancelled tooltip never appears later at the new cursor position", context do
        assert icon_menu_state().tooltip == nil
        {:ok, context}
      end

      when_ "the pointer remains over File for the configured delay", context do
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_file)
        Probes.send_mouse_move(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2)
        Process.sleep(700)
        {:ok, context}
      end

      then_ "the component displays its optional tooltip", context do
        assert icon_menu_state().tooltip.text == "File commands"
        {:ok, context}
      end

      when_ "the pointer moves away", context do
        Probes.send_mouse_move(10, 100)
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the tooltip is dismissed immediately", context do
        assert icon_menu_state().tooltip == nil
        {:ok, context}
      end

      when_ "the rightmost Help icon is hovered", context do
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_help)
        Probes.send_mouse_move(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2)
        Process.sleep(700)
        {:ok, context}
      end

      then_ "its tooltip flips left to remain inside the window", context do
        component = icon_menu_component()
        tooltip = Scenic.Graph.get!(component.assigns.graph, :menu_tooltip)
        {x, _y} = Scenic.Primitive.get_transform(tooltip, :translate)
        assert x < 0
        assert component.assigns.state.tooltip.text == "Help and keyboard shortcuts"
        {:ok, context}
      end

      when_ "an explanatory View setting row is hovered", context do
        Probes.click_element("icon_menu_view")
        Process.sleep(100)
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_view_action_feedback)
        Probes.send_mouse_move(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2)
        Process.sleep(700)
        {:ok, context}
      end

      then_ "the individual row explains what the toggle changes", context do
        assert icon_menu_state().tooltip.text =~ "copied text, undo, and reload"
        {:ok, context}
      end
    end
  end

  defp icon_menu_state do
    icon_menu_component().assigns.state
  end

  defp icon_menu_component do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :icon_menu)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end
end
