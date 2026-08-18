defmodule Quillex.Structs.BufState do
  alias Quillex.Structs.BufState.Cursor

  @unnamed "unnamed"

  @type source :: %{filepath: String.t()} | nil
  @type selection :: %{start: {pos_integer, pos_integer}, end: {pos_integer, pos_integer}} | nil
  @type t :: %__MODULE__{
          uuid: String.t() | nil,
          name: String.t(),
          data: [String.t()] | nil,
          source: source(),
          cursor: Cursor.t(),
          selection: selection(),
          read_only?: boolean(),
          dirty?: boolean(),
          external_change: nil | :modified | :deleted,
          undo_stack: list(),
          redo_stack: list(),
          undo_max_size: pos_integer(),
          search_query: String.t() | nil,
          search_opts: keyword(),
          search_matches: list(),
          search_current_index: non_neg_integer()
        }

  defstruct [
    # a unique uuid for referencing the buffer
    uuid: nil,
    # the name of the buffer that appears in the tab-bar (NOT unique!)
    name: @unnamed,
    # where the actual contents of the buffer is kept
    data: nil,
    # Description of where this buffer originally came from, e.g. %{filepath: file_path}
    source: nil,
    # Singular document cursor; multi-cursor/Vim scaffolding was removed in 0.7.3.
    cursor: nil,
    # text selection state - tracks start and end of selection
    # %{start: {line, col}, end: {line, col}} or nil for no selection
    selection: nil,
    # a flag which lets us know if it's a read-only buffer, read-only buffers can't be modified
    read_only?: false,
    # a `dirty` buffer is one which is changed / modified in memory but not yet written to disk
    dirty?: false,
    # Set by ExternalFileSync when disk changes cannot be applied safely.
    external_change: nil,

    # ===== UNDO/REDO STATE (Single Source of Truth) =====
    # List of {data, cursor, selection} snapshots for undo (most recent first)
    undo_stack: [],
    # List of {data, cursor, selection} snapshots for redo (most recent first)
    redo_stack: [],
    # Maximum undo stack size
    undo_max_size: 100,

    # ===== SEARCH STATE (Single Source of Truth) =====
    # Current search query string (nil = not searching)
    search_query: nil,
    # How to interpret that query: :case_sensitive and :regex, both default
    # false. Held per buffer alongside the query itself, because every later
    # recompute — resync after an edit, the rescan after a replace — has to
    # read the document the same way the original search did.
    search_opts: [],
    # List of {line, col, match_text} tuples for all matches
    search_matches: [],
    # Current match index (0-based)
    search_current_index: 0
  ]

  @doc """
  Create a new BufState from a map of arguments.

  ## Parameters
  - `args` - Map with optional keys: `:name`, `:data`, `:source`, `:cursor`,
    `:read_only?`, `:undo_max_size`

  ## Returns
  A `%BufState{}` struct with a freshly generated UUID.
  """
  @spec new(map()) :: t()
  def new(args) when is_map(args) do
    name = Map.get(args, :name) || Map.get(args, "name") || @unnamed
    data = Map.get(args, :data) || Map.get(args, "data") || [""]
    data = if is_list(data), do: data, else: raise("Buffer data must be a list of strings")
    source = Map.get(args, :source) || Map.get(args, "source") || nil
    cursor = Map.get(args, :cursor) || Map.get(args, "cursor") || Cursor.new()
    read_only? = Map.get(args, :read_only?) || Map.get(args, "read_only?") || false

    %__MODULE__{
      uuid: UUID.uuid4(),
      name: name,
      data: data,
      source: source,
      cursor: cursor,
      selection: nil,
      read_only?: read_only?,
      dirty?: false,
      external_change: nil,
      # Undo/Redo - start with empty stacks
      undo_stack: [],
      redo_stack: [],
      undo_max_size: Map.get(args, :undo_max_size) || 100,
      # Search - start with no search
      search_query: nil,
      search_opts: [],
      search_matches: [],
      search_current_index: 0
    }
  end
end
