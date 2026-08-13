defmodule Quillex.TabBarScrollScopeSpex do
  @moduledoc """
  An overflowing TabBar owns wheel input only while the pointer is over it.

  TabBar requests scroll globally because no tab primitive owns wheel input;
  this regression ensures that request does not make editor or navigator wheel
  gestures move the tab strip as a side effect.
  """
  use SexySpex

  alias Quillex.Buffer.BufferManager
  alias ScenicMcp.Probes

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()

    for index <- 1..12 do
      {:ok, _ref} = BufferManager.new_buffer("overflowing-tab-#{index}.ex")
    end

    first = BufferManager.list_buffers() |> List.first()
    BufferManager.activate_buffer(first)
    BufferManager.sync()
    Process.sleep(700)
    :ok
  end

  defp tab_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :tab_bar)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state
  end

  spex "Tab-bar wheel input is pointer-scoped",
    description: "Scrolling editor content cannot move the overflowing tab strip",
    tags: [:phase_34, :tab_bar, :scroll, :input_routing] do
    scenario "Wheel outside and then inside the tab bar" do
      given_ "an overflowing tab strip positioned at its left edge", context do
        state = tab_state()
        assert ScenicWidgets.TabBar.State.max_scroll_offset(state) > 0
        assert state.scroll_offset == 0
        {:ok, context}
      end

      when_ "the wheel moves over the editor pane", context do
        Probes.send_scroll(0, -3, 500, 400)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the tab strip remains fixed", context do
        assert tab_state().scroll_offset == 0
        {:ok, context}
      end

      when_ "the same wheel gesture occurs over the tab bar", context do
        Probes.send_scroll(0, -3, 300, 17)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the tab strip scrolls", context do
        assert tab_state().scroll_offset > 0
        {:ok, context}
      end
    end
  end
end
