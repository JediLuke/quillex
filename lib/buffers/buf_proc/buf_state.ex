defmodule Quillex.Structs.BufState do
  alias Quillex.Structs.BufState.Cursor

  @unnamed "unnamed"

  @type source :: %{filepath: String.t()} | nil
  @type selection :: %{start: {pos_integer, pos_integer}, end: {pos_integer, pos_integer}} | nil
  @type timestamps :: %{
    opened: DateTime.t() | nil,
    last_update: DateTime.t() | nil,
    last_save: DateTime.t() | nil
  }

  @type t :: %__MODULE__{
    uuid: String.t() | nil,
    name: String.t(),
    type: :text,
    data: [String.t()] | nil,
    mode: :edit | {:vim, :insert} | {:vim, :normal},
    source: source(),
    cursors: [Cursor.t()],
    selection: selection(),
    history: list(),
    read_only?: boolean(),
    dirty?: boolean(),
    undo_stack: list(),
    redo_stack: list(),
    undo_max_size: pos_integer(),
    search_query: String.t() | nil,
    search_matches: list(),
    search_current_index: non_neg_integer(),
    timestamps: timestamps()
  }

  defstruct [
    # a unique uuid for referencing the buffer
    uuid: nil,
    # the name of the buffer that appears in the tab-bar (NOT unique!)
    name: @unnamed,
    # There are several types of buffers e.g. :text, :list - the most common though is :text
    type: :text,
    # where the actual contents of the buffer is kept
    data: nil,
    # Buffers can be in various "modes" e.g. {:vim, :normal}, :edit
    mode: :edit,
    # Description of where this buffer originally came from, e.g. %{filepath: file_path}
    source: nil,
    # a list of all the cursors in the buffer (these go into the buffer, not the buffer pane, because cursors are still used even through the API)
    cursors: [],
    # text selection state - tracks start and end of selection
    selection: nil,  # %{start: {line, col}, end: {line, col}} or nil for no selection
    # track all the modifications as we do them, for undo/redo purposes
    history: [],
    # a flag which lets us know if it's a read-only buffer, read-only buffers can't be modified
    read_only?: false,
    # a `dirty` buffer is one which is changed / modified in memory but not yet written to disk
    dirty?: false,

    # ===== UNDO/REDO STATE (Single Source of Truth) =====
    # List of {data, cursors, selection} snapshots for undo (most recent first)
    undo_stack: [],
    # List of {data, cursors, selection} snapshots for redo (most recent first)
    redo_stack: [],
    # Maximum undo stack size
    undo_max_size: 100,

    # ===== SEARCH STATE (Single Source of Truth) =====
    # Current search query string (nil = not searching)
    search_query: nil,
    # List of {line, col, match_text} tuples for all matches
    search_matches: [],
    # Current match index (0-based)
    search_current_index: 0,

    # Where we track the timestamps for various operations
    timestamps: %{
      opened: nil,
      last_update: nil,
      last_save: nil
    }
  ]

  #   @valid_types [:text, :list]
  #   @vim_modes [{:vim, :insert}, {:vim, :normal}]
  #   @valid_modes [:edit] ++ @vim_modes

  @doc """
  Create a new BufState from a map of arguments.

  ## Parameters
  - `args` - Map with optional keys: `:name`, `:data`, `:mode`, `:source`, `:cursors`,
    `:read_only?`, `:undo_max_size`

  ## Returns
  A `%BufState{}` struct with a freshly generated UUID and the opened timestamp set.
  """
  @spec new(map()) :: t()
  def new(args) when is_map(args) do
    name = Map.get(args, :name) || Map.get(args, "name") || @unnamed
    data = Map.get(args, :data) || Map.get(args, "data") || [""]
    data = if is_list(data), do: data, else: raise("Buffer data must be a list of strings")
    # mode: validate_mode(args[:mode]) || :edit,
    mode = Map.get(args, :mode) || Map.get(args, "mode") || :edit
    # Creating buffer with mode: #{inspect(mode)}
    source = Map.get(args, :source) || Map.get(args, "source") || nil
    cursors = Map.get(args, :cursors) || Map.get(args, "cursors") || [Cursor.new()]
    # scroll_acc = Map.get(args, :scroll_acc) || Map.get(args, "scroll_acc") || {0, 0}
    read_only? = Map.get(args, :read_only?) || Map.get(args, "read_only?") || false

    %__MODULE__{
      uuid: UUID.uuid4(),
      name: name,
      type: :text,
      data: data,
      mode: mode,
      source: source,
      cursors: cursors,
      selection: nil,
      history: [],
      read_only?: read_only?,
      dirty?: false,
      # Undo/Redo - start with empty stacks
      undo_stack: [],
      redo_stack: [],
      undo_max_size: Map.get(args, :undo_max_size) || 100,
      # Search - start with no search
      search_query: nil,
      search_matches: [],
      search_current_index: 0,
      timestamps: %{
        # TODO use some kind of default timezone
        opened: DateTime.utc_now()
      }
    }
  end

end
