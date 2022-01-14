defmodule QuillEx.Utils.Themes do
  alias Scenic.Primitive.Style.Theme

  @default_theme :light

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
    (opts[:theme] || Theme.preset(@default_theme))
    |> Theme.normalize()
  end
end
