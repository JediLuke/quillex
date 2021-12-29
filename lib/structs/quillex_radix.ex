defmodule QuillEx.Structs.Radix do
    defstruct [
        buffers: [],
        active_buf: nil,
        gui_config: %{
            menu_bar: %{
                height: 60,
                item_width: 180, #TODO make this also maybe flexible, with a max cap
            },
            tab_selector: %{
                height: 40
            },
            fonts: %{
                primary: :ibm_plex_mono
            }
        }
    ]

end