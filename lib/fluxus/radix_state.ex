defmodule QuillEx.Fluxus.Structs.RadixState do
   alias ScenicWidgets.TextPad.Structs.Font


  def new do
    {:ok, {_type, ibm_plex_mono_font_metrics}} = Scenic.Assets.Static.meta(:ibm_plex_mono)

    %{
      root: %{
        active_app: :editor,
        graph: nil,
        # layers: []
      },
      gui: %{
        viewport: nil,
      },
      desktop: %{
        menu_bar: %{
          height: 60,
          button_width: 180,
          font: %{
            name: :ibm_plex_mono,
            size: 36,
            metrics: ibm_plex_mono_font_metrics
          }
        },
      },
      editor: %{
        font: ScenicWidgets.TextPad.Structs.Font.new(%{
          name: :ibm_plex_mono,
          size: 24,
          metrics: ibm_plex_mono_font_metrics
        }),
        buffers: [],
        active_buf: nil,
        config: %{
          scroll: %{
            # invert: %{ # change the direction of scroll wheel
            #   horizontal?: true,
            #   vertical?: false
            # },
            speed: %{ # higher value means faster scrolling
              horizontal: 5,
              vertical: 3
            }
          }
        }
      }
    }
  end

end
