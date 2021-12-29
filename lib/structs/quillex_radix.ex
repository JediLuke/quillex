defmodule QuillEx.Structs.Radix do
    defstruct [
        buffers: [],
        cursors: %{},
        theme: :dark,
        active_buf: nil,
        gui_config: %{}
    ]

    def new do
        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        %__MODULE__{
            gui_config: %{
                menu_bar: %{
                    height: 60,
                    item_width: 180, #TODO make this also maybe flexible, with a max cap
                },
                tab_selector: %{
                    height: 40
                },
                fonts: %{
                    primary: %{name: :ibm_plex_mono, metrics: ibm_plex_mono_fm}
                }
            }
        }
    end
end