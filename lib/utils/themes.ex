defmodule QuillEx.Utils.Themes do

    # `theme` is passed in as an inherited style by Scenic - e.g.
    #
    # %{
    #     active: {58, 94, 201},
    #     background: {72, 122, 252},
    #     border: :light_grey,
    #     focus: :cornflower_blue,
    #     highlight: :sandy_brown,
    #     text: :white,
    #     thumb: :cornflower_blue
    # }

    def theme(opts) do
        case opts[:theme] do
            nil -> Scenic.Primitive.Style.Theme.preset(:primary)
            :dark -> Scenic.Primitive.Style.Theme.preset(:primary)
            :light -> Scenic.Primitive.Style.Theme.preset(:primary)
            theme -> theme
        end
        |> Scenic.Primitive.Style.Theme.normalize() 
    end
end