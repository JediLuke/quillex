defmodule Quillex.Buffer.ContribClipboard do
  @moduledoc """
  The widget library's clipboard, pointed at quillex's.

  Direct-mode TextFields — the search pane's query and replacement fields —
  paste through `ScenicWidgets.Clipboard`, not through the buffer. Left to
  its own default that widget clipboard chooses its own tools, so the pane
  and the editor could disagree about what "the clipboard" is, and only one
  of them honoured the `:clipboard_commands` config. Routing the widget
  through `Quillex.Buffer.ClipboardAdapter` gives quillex a single clipboard,
  and gives the test suite its file-backed one for free.
  """
  @behaviour ScenicWidgets.Clipboard

  alias Quillex.Buffer.ClipboardAdapter

  @impl true
  def copy(text) when is_binary(text), do: ClipboardAdapter.copy_result(text)

  @impl true
  def paste do
    case ClipboardAdapter.paste_result() do
      text when is_binary(text) -> {:ok, text}
      {:error, reason} -> {:error, reason}
    end
  end
end
