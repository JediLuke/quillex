defmodule Quillex.GUI.Theme do
  @moduledoc "Application visual tokens shared by editor and navigation."

  def editor_font(size) when size in 12..32 do
    {:ok, {Scenic.Assets.Static.Font, metrics}} = Scenic.Assets.Static.meta(:ibm_plex_mono)
    %{name: :ibm_plex_mono, size: size, metrics: metrics}
  end

  def editor_colors do
    %{text: :white, slate: :medium_slate_blue}
  end
end
