defmodule QuillEx.RadixState do


  def new do
    {:ok, {_type, ibm_plex_mono_fm}} = Scenic.Assets.Static.meta(:ibm_plex_mono)
    {:ok, {_type, iosevka_fm}} = Scenic.Assets.Static.meta(:iosevka)

    %{
      root: %{
        active_app: :editor,
        graph: nil,
        layers: [
          one: nil,
          two: nil,
          three: nil,
          four: nil
        ]
      },
      editor: %{
        graph: nil,
        buffers: [],
        active_buf: nil,
        config: %{}
      },
      overlay: %{},
      gui_config: %{
        menu_bar: %{
          height: 60,
          item_width: 180
        },
        tab_selector: %{
          height: 40
        },
        fonts: %{
          primary: %{
            name: :ibm_plex_mono,
            metrics: ibm_plex_mono_fm,
            size: 24
          },
          menu_bar: %{
            name: :iosevka,
            size: 36,
            metrics: iosevka_fm
          }
        }
      }
    }
  end

  def change_font(%{gui_config: %{fonts: %{primary: current_font}}} = current_radix_state, new_font) when is_atom(new_font) do
    {:ok, {_type, new_font_metrics}} = Scenic.Assets.Static.meta(new_font)

    full_new_font_map = current_font |> Map.merge(%{name: new_font, metrics: new_font_metrics})

    current_radix_state
    |> put_in([:gui_config, :fonts, :primary], full_new_font_map)
  end

  def change_font_size(%{gui_config: %{fonts: %{primary: current_font}}} = current_radix_state, direction) when direction in [:increase, :decrease] do
    delta = if direction == :increase, do: 4, else: -4
    full_new_font_map = current_font |> Map.merge(%{size: current_font.size + delta})

    current_radix_state
    |> put_in([:gui_config, :fonts, :primary], full_new_font_map)
  end
end
