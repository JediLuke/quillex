defmodule QuillEx.Fluxus.Structs.RadixState do
   alias ScenicWidgets.TextPad.Structs.Font


  def new do
    {:ok, {_type, ibm_plex_mono_font_metrics}} = Scenic.Assets.Static.meta(:ibm_plex_mono)

    %{
      root: %{
        active_app: :editor,
        graph: nil,
        layers: []
      },
      editor: %{
        graph: nil,
        buffers: [], # A list of %Buffer{} structs
        active_buf: nil,
        config: %{},
      },
      menu_bar: %{
        height: 60
      },
      gui: %{
        viewport: nil,
        fonts: %{
          primary: ScenicWidgets.TextPad.Structs.Font.new(%{
             name: :ibm_plex_mono,
             metrics: ibm_plex_mono_font_metrics
          })
       }
      },


      # overlay: %{},
      
      gui_config: %{
        menu_bar: %{
          height: 60,
          item_width: 180
        },
        tab_selector: %{
          height: 40
        },
        fonts: %{
          primary: Font.new(%{
            name: :ibm_plex_mono,
            size: 24,
            metrics: ibm_plex_mono_font_metrics
          }),
          menu_bar: Font.new(%{
            name: :ibm_plex_mono,
            size: 36,
            metrics: ibm_plex_mono_font_metrics
          })
        },
        editor: %{
          # invert_scroll: %{ # change the direction of scroll wheel
          #   horizontal?: true,
          #   vertical?: false
          # },
          scroll_speed: %{ # higher value means faster scrolling
            horizontal: 5,
            vertical: 3
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

  def change_editor_scroll_state(current_radix_state, %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state) do
    current_radix_state
    |> put_in([:editor, :scroll_state], new_scroll_state)
  end
end
