defmodule ScenicWidgets.ConfirmDialogTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.ConfirmDialog

  # A minimal frame struct that satisfies the frame validation.
  @sample_frame %{size: %{width: 800, height: 600}}

  @sample_buttons [
    {:save, "Save"},
    {:discard, "Discard"},
    {:cancel, "Cancel"}
  ]

  # ─────────────────────────────────────────────────────────────
  # validate/1
  # ─────────────────────────────────────────────────────────────

  describe "validate/1 — success" do
    test "accepts a fully populated data map" do
      data = %{
        frame: @sample_frame,
        title: "Unsaved Changes",
        message: "Save changes before closing?",
        buttons: @sample_buttons
      }

      assert {:ok, ^data} = ConfirmDialog.validate(data)
    end

    test "accepts a single-button list" do
      data = %{
        frame: @sample_frame,
        title: "Confirm",
        message: "Are you sure?",
        buttons: [{:ok, "OK"}]
      }

      assert {:ok, _} = ConfirmDialog.validate(data)
    end

    test "accepts two-button list" do
      data = %{
        frame: @sample_frame,
        title: "Delete",
        message: "This cannot be undone.",
        buttons: [{:confirm, "Delete"}, {:cancel, "Cancel"}]
      }

      assert {:ok, _} = ConfirmDialog.validate(data)
    end

    test "passes through extra keys untouched" do
      data = %{
        frame: @sample_frame,
        title: "Hi",
        message: "Hello world",
        buttons: [{:ok, "OK"}],
        id: :my_dialog
      }

      assert {:ok, returned} = ConfirmDialog.validate(data)
      assert returned[:id] == :my_dialog
    end
  end

  describe "validate/1 — failure: missing keys" do
    test "returns error when :frame is missing" do
      data = %{title: "T", message: "M", buttons: [{:ok, "OK"}]}
      assert {:error, msg} = ConfirmDialog.validate(data)
      assert is_binary(msg)
    end

    test "returns error when :title is missing" do
      data = %{frame: @sample_frame, message: "M", buttons: [{:ok, "OK"}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end

    test "returns error when :message is missing" do
      data = %{frame: @sample_frame, title: "T", buttons: [{:ok, "OK"}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end

    test "returns error when :buttons is missing" do
      data = %{frame: @sample_frame, title: "T", message: "M"}
      assert {:error, _} = ConfirmDialog.validate(data)
    end
  end

  describe "validate/1 — failure: invalid field types" do
    test "returns error when :title is not a string" do
      data = %{frame: @sample_frame, title: :not_a_string, message: "M", buttons: [{:ok, "OK"}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end

    test "returns error when :message is not a string" do
      data = %{frame: @sample_frame, title: "T", message: 42, buttons: [{:ok, "OK"}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end

    test "returns error when :frame is not a map" do
      data = %{frame: "not_a_map", title: "T", message: "M", buttons: [{:ok, "OK"}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end
  end

  describe "validate/1 — failure: invalid buttons" do
    test "returns error for an empty buttons list" do
      data = %{frame: @sample_frame, title: "T", message: "M", buttons: []}
      assert {:error, msg} = ConfirmDialog.validate(data)
      assert String.contains?(msg, "non-empty")
    end

    test "returns error when a button tuple has a non-atom action" do
      data = %{frame: @sample_frame, title: "T", message: "M", buttons: [{"save", "Save"}]}
      assert {:error, msg} = ConfirmDialog.validate(data)
      assert String.contains?(msg, "atom")
    end

    test "returns error when a button tuple has a non-string label" do
      data = %{frame: @sample_frame, title: "T", message: "M", buttons: [{:save, :not_a_string}]}
      assert {:error, msg} = ConfirmDialog.validate(data)
      assert String.contains?(msg, "string")
    end

    test "returns error when a button entry is not a tuple" do
      data = %{frame: @sample_frame, title: "T", message: "M", buttons: [:bad]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end

    test "returns error when a button entry is a 3-tuple" do
      data = %{frame: @sample_frame, title: "T", message: "M", buttons: [{:save, "Save", :extra}]}
      assert {:error, _} = ConfirmDialog.validate(data)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # button_color/1
  # ─────────────────────────────────────────────────────────────

  describe "button_color/1" do
    test ":save returns green" do
      assert {60, 130, 70} = ConfirmDialog.button_color(:save)
    end

    test ":discard returns orange" do
      assert {170, 100, 30} = ConfirmDialog.button_color(:discard)
    end

    test ":cancel returns grey" do
      assert {80, 80, 85} = ConfirmDialog.button_color(:cancel)
    end

    test "unknown atom returns fallback grey" do
      assert {80, 80, 85} = ConfirmDialog.button_color(:something_else)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # button_bounds/1
  # ─────────────────────────────────────────────────────────────

  describe "button_bounds/1 — layout geometry" do
    test "returns one bound entry per button" do
      bounds = ConfirmDialog.button_bounds(@sample_buttons)
      assert length(bounds) == 3
    end

    test "each entry is {action, x, y, width, height}" do
      [first | _] = ConfirmDialog.button_bounds(@sample_buttons)
      assert {action, x, y, w, h} = first
      assert is_atom(action)
      assert is_number(x) and is_number(y)
      assert is_number(w) and is_number(h)
    end

    test "actions preserve the order of the input list" do
      bounds = ConfirmDialog.button_bounds(@sample_buttons)
      actions = Enum.map(bounds, fn {action, _, _, _, _} -> action end)
      assert actions == [:save, :discard, :cancel]
    end

    test "buttons share the same y-offset" do
      bounds = ConfirmDialog.button_bounds(@sample_buttons)
      ys = Enum.map(bounds, fn {_, _, y, _, _} -> y end)
      assert Enum.uniq(ys) |> length() == 1
    end

    test "each subsequent button x is offset by button_width + button_spacing" do
      bounds = ConfirmDialog.button_bounds([{:a, "A"}, {:b, "B"}, {:c, "C"}])
      [{_, x0, _, _, _}, {_, x1, _, _, _}, {_, x2, _, _, _}] = bounds
      step = x1 - x0
      assert_in_delta step, x2 - x1, 0.001
      # step must equal @button_width + @button_spacing = 100 + 16 = 116
      assert_in_delta step, 116.0, 0.001
    end

    test "button row is centred within the dialog width" do
      buttons = [{:ok, "OK"}]
      [{_, x, _, w, _}] = ConfirmDialog.button_bounds(buttons)
      # For a single button: start_x = (420 - 100) / 2 = 160
      assert_in_delta x, 160.0, 0.001
      assert_in_delta w, 100.0, 0.001
    end

    test "three-button row is centred within the dialog width" do
      bounds = ConfirmDialog.button_bounds(@sample_buttons)
      [{_, x0, _, _, _} | _] = bounds
      {_, x2, _, bw, _} = List.last(bounds)
      # row spans from x0 to x2 + button_width
      row_start = x0
      row_end = x2 + bw
      # midpoint of row should equal midpoint of @dialog_width = 420
      mid_row = (row_start + row_end) / 2
      mid_dialog = 420 / 2
      assert_in_delta mid_row, mid_dialog, 0.001
    end

    test "single-button returns correct height" do
      [{_, _, _, _, h}] = ConfirmDialog.button_bounds([{:ok, "OK"}])
      assert_in_delta h, 32.0, 0.001
    end

    test "long labels widen their buttons instead of overflowing" do
      [{_, _, _, width, _}] = ConfirmDialog.button_bounds([{:save, "Save as Default"}])
      assert width > 100
      assert width <= 160
    end
  end
end
