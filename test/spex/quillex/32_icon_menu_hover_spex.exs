defmodule Quillex.IconMenuHoverSpex do
  @moduledoc """
  The toolbar hover is a reversible background highlight. Moving into sibling
  content must clear it, and hovering must not recolor the icon glyph.
  """
  use SexySpex

  alias ScenicMcp.Probes

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    Quillex.TestHelpers.AppReset.reset!()
    :ok
  end

  defp icon_menu_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :icon_menu)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  defp icon_styles(graph, menu_id) do
    graph
    |> Scenic.Graph.get({:icon_text, menu_id})
    |> Enum.map(fn primitive ->
      {Scenic.Primitive.get_style(primitive, :fill),
       Scenic.Primitive.get_style(primitive, :stroke)}
    end)
  end

  defp background_fill(graph, menu_id) do
    [background] = Scenic.Graph.get(graph, {:icon_bg, menu_id})
    Scenic.Primitive.get_style(background, :fill)
  end

  spex "Toolbar icon hover clears when the pointer leaves",
    description: "Hover changes only the background and reverts over sibling content",
    tags: [:phase_32, :icon_menu, :hover] do
    scenario "Hovering File and then moving into the editor" do
      given_ "the unhovered File icon", context do
        Probes.send_mouse_move(500, 300)
        Process.sleep(200)

        scene = icon_menu_scene()
        root = :sys.get_state(Process.whereis(QuillEx.RootScene))
        width = root.assigns.state.frame.size.width

        {:ok,
         Map.merge(context, %{
           file_x: width - 140 + 17,
           icon_styles: icon_styles(scene.assigns.graph, :file),
           background: background_fill(scene.assigns.graph, :file)
         })}
      end

      when_ "the pointer enters the File icon", context do
        Probes.send_mouse_move(context.file_x, 17)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "only its background is highlighted", context do
        scene = icon_menu_scene()
        assert scene.assigns.state.hovered_menu == :file
        assert background_fill(scene.assigns.graph, :file) != context.background
        assert icon_styles(scene.assigns.graph, :file) == context.icon_styles
        {:ok, context}
      end

      when_ "the pointer moves into the editor pane", context do
        Probes.send_mouse_move(500, 300)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the File icon returns to its normal appearance", context do
        scene = icon_menu_scene()
        assert scene.assigns.state.hovered_menu == nil
        assert background_fill(scene.assigns.graph, :file) == context.background
        assert icon_styles(scene.assigns.graph, :file) == context.icon_styles
        {:ok, context}
      end
    end
  end
end
