defmodule Quillex.TestHelpers.SemanticProbe do
  @moduledoc """
  Dump what the semantic layer actually contains, for when a spex says an
  element is missing and you need to know *why*.

  This exists because "element not found" has several distinct causes that
  look identical from a test, and guessing between them has burned real time:

  - the element was never registered (component didn't run its registration);
  - it was registered in `semantic_table` but not `semantic_index`, so
    id-based lookup misses it while a table scan finds it;
  - it is registered under a different ID SHAPE than the lookup uses — atoms
    for static names, strings for ids derived from runtime data such as
    buffer UUIDs (this one caused AUD-028);
  - it is registered but positioned outside its container, so the click
    lands somewhere else entirely (AUD-026).

  Nothing here asserts. It is for reading, from an iex session or a
  temporarily-instrumented spex:

      alias Quillex.TestHelpers.SemanticProbe
      SemanticProbe.dump("icon_menu_file")
      SemanticProbe.ids(~r/tab_bar/)
  """

  @doc """
  Everything known about one element id, following the same path
  `Scenic.ViewPort.Semantic` takes.

  Accepts the id in whatever shape you have it — atom, string, or tuple —
  and reports which shape actually resolved, which is usually the answer.
  """
  def dump(element_id) do
    with {:ok, vp} <- viewport() do
      candidates =
        case element_id do
          id when is_binary(id) -> [id, existing_atom(id)] |> Enum.reject(&is_nil/1)
          id -> [id]
        end

      resolved =
        Enum.find_value(candidates, fn id ->
          case :ets.lookup(vp.semantic_index, id) do
            [{^id, key}] -> {id, key}
            [] -> nil
          end
        end)

      %{
        queried: element_id,
        tried: candidates,
        index_hit: resolved,
        entry:
          case resolved do
            {_id, key} ->
              case :ets.lookup(vp.semantic_table, key) do
                [{^key, entry}] -> entry
                [] -> {:error, :index_points_at_missing_table_row}
              end

            nil ->
              {:error, :not_in_index}
          end
      }
    end
  end

  @doc "Every registered id matching `pattern`, split by which table holds it."
  def ids(pattern \\ ~r//) do
    with {:ok, vp} <- viewport() do
      match? = fn key -> Regex.match?(pattern, inspect(key)) end

      index_ids =
        vp.semantic_index |> :ets.tab2list() |> Enum.map(&elem(&1, 0)) |> Enum.filter(match?)

      table_keys =
        vp.semantic_table |> :ets.tab2list() |> Enum.map(&elem(&1, 0)) |> Enum.filter(match?)

      %{
        index: Enum.sort_by(index_ids, &inspect/1),
        table: Enum.sort_by(table_keys, &inspect/1),
        # Registered for rendering but not resolvable by id — the shape that
        # makes click_element fail on an element you can plainly see.
        in_table_only:
          table_keys
          |> Enum.map(fn
            {_scene, id} -> id
            other -> other
          end)
          |> Enum.reject(&(&1 in index_ids))
          |> Enum.sort_by(&inspect/1)
      }
    end
  end

  @doc """
  Where an element would actually be clicked, and whether that point lies
  within the bounds of `container_id`.

  A false here means the semantic layer is advertising something the user
  cannot reach — see AUD-026.
  """
  def click_target(element_id, container_id \\ nil) do
    with %{entry: %{screen_bounds: %{left: l, top: t, width: w, height: h}}} <- dump(element_id) do
      point = {l + w / 2, t + h / 2}

      case container_id && dump(container_id) do
        %{entry: %{screen_bounds: %{left: cl, top: ct, width: cw, height: ch}}} ->
          {cx, cy} = point

          %{
            point: point,
            container: {cl, ct, cw, ch},
            inside?: cx >= cl and cx <= cl + cw and cy >= ct and cy <= ct + ch
          }

        _ ->
          %{point: point}
      end
    end
  end

  defp viewport, do: Scenic.ViewPort.info(:main_viewport)

  defp existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end
end
