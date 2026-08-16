defmodule Quillex.RadixCache.Sources do
  @moduledoc """
  The single place RadixCache Scenic.PubSub source ids are minted.

  Scenic.PubSub sources must be atoms. Per-buffer sources are derived from the
  buffer uuid — bounded by the number of open buffers, so dynamic atom
  creation is safe here.
  """

  @doc "Buffer-list store source: `%{buffers: [Ref], active_buf: Ref | nil}`"
  def buffers, do: :radix_buffers

  @doc "UI chrome store source (ViewStore state map)"
  def view, do: :radix_view

  @doc "Project-wide search: query, scope, results (`Quillex.RadixCache.ProjectSearchStore`)."
  def project_search, do: :radix_project_search

  @doc "Token spans for the pane's document (`Quillex.RadixCache.HighlightStore`)."
  def highlights, do: :radix_highlights

  @doc "Per-buffer store source: the full BufState snapshot for one buffer"
  def buffer(uuid) when is_binary(uuid), do: :"radix_buf_#{uuid}"

  @doc "Per-pane source: what a pane's text surface displays (see PaneStore)"
  def pane(pane_id) when is_atom(pane_id), do: :"radix_pane_#{pane_id}"
end
