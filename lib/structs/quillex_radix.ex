defmodule QuillEx.Structs.Radix do
  defstruct buffers: [],
            theme: :dark,
            active_buf: nil,
            gui_config: %{}

  def new do
    {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    %__MODULE__{
      gui_config: %{
        menu_bar: %{
          height: 60,
          # TODO make this also maybe flexible, with a max cap
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
          }
        }
      }
    }
  end
end
