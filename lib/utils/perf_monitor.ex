defmodule Quillex.PerfMonitor do
  @moduledoc """
  Frame-time and handler-time performance monitor.

  Hooks into Scenic's driver telemetry ([:render, :start] / [:render, :finish])
  to measure GPU render time, and provides `measure/2` for instrumenting
  Elixir-side handler cost (the time between receiving an event and calling push_graph).

  ## Usage

  Started automatically by the supervision tree. Access metrics:

      Quillex.PerfMonitor.stats()
      #=> %{fps: 58.2, avg_render_ms: 4.1, avg_handler_ms: 12.3,
      #     max_render_ms: 8.0, max_handler_ms: 45.0, frame_count: 342,
      #     slow_frames: 3, handler_histogram: %{...}}

  Instrument a handler:

      Quillex.PerfMonitor.measure(:scroll, fn ->
        # ... compute graph, push_graph ...
        {:noreply, scene}
      end)

  The result of the function is passed through unchanged.
  """

  use GenServer
  require Logger

  # rolling window of frames for FPS calc
  @window_size 120
  # > 1 frame at 60fps
  @slow_threshold_ms 16.67
  # log summary every 5s
  @report_interval_ms 5_000

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return current performance stats."
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{error: :not_running}
  end

  @doc "Reset all counters to zero. Useful for collecting clean baselines for a specific scenario."
  def reset do
    GenServer.call(__MODULE__, :reset)
  catch
    :exit, _ -> {:error, :not_running}
  end

  @doc """
  Measure the wall-clock time of a handler function.
  Tags the measurement with a label (e.g. :scroll, :state_update, :render_graph).
  Returns the result of the function unchanged.
  """
  def measure(label, fun) when is_function(fun, 0) do
    t0 = :erlang.monotonic_time(:microsecond)

    try do
      fun.()
    after
      elapsed_us = :erlang.monotonic_time(:microsecond) - t0
      GenServer.cast(__MODULE__, {:handler_sample, label, elapsed_us})
    end
  end

  # --- GenServer ---

  @impl GenServer
  def init(_opts) do
    # Attach telemetry handlers for Scenic driver render events
    :telemetry.attach(
      "quillex-render-start",
      [:render, :start],
      &__MODULE__.handle_telemetry/4,
      nil
    )

    :telemetry.attach(
      "quillex-render-finish",
      [:render, :finish],
      &__MODULE__.handle_telemetry/4,
      nil
    )

    Process.send_after(self(), :report, @report_interval_ms)

    {:ok,
     %{
       # Render (GPU) timing
       render_start: nil,
       render_times: :queue.new(),
       render_count: 0,
       render_max_ms: 0.0,

       # Handler (Elixir) timing — per-label
       # label => {count, total_us, max_us, recent_queue}
       handler_samples: %{},

       # FPS tracking
       frame_timestamps: :queue.new(),
       slow_frames: 0
     }}
  end

  # Telemetry callbacks — run in the driver process, send to our GenServer
  def handle_telemetry([:render, :start], %{timestamp: ts}, _meta, _config) do
    GenServer.cast(__MODULE__, {:render_start, ts})
  catch
    :exit, _ -> :ok
  end

  def handle_telemetry([:render, :finish], %{timestamp: ts}, _meta, _config) do
    GenServer.cast(__MODULE__, {:render_finish, ts})
  catch
    :exit, _ -> :ok
  end

  @impl GenServer
  def handle_cast({:render_start, ts}, state) do
    {:noreply, %{state | render_start: ts}}
  end

  def handle_cast({:render_finish, _ts}, %{render_start: nil} = state) do
    # Got finish without start — skip
    {:noreply, state}
  end

  def handle_cast({:render_finish, finish_ts}, state) do
    elapsed_ns = finish_ts - state.render_start
    elapsed_ms = elapsed_ns / 1_000_000

    render_times = queue_push(state.render_times, elapsed_ms, @window_size)
    frame_timestamps = queue_push(state.frame_timestamps, finish_ts, @window_size)

    slow_frames =
      if elapsed_ms > @slow_threshold_ms,
        do: state.slow_frames + 1,
        else: state.slow_frames

    {:noreply,
     %{
       state
       | render_start: nil,
         render_times: render_times,
         render_count: state.render_count + 1,
         render_max_ms: max(state.render_max_ms, elapsed_ms),
         frame_timestamps: frame_timestamps,
         slow_frames: slow_frames
     }}
  end

  def handle_cast({:handler_sample, label, elapsed_us}, state) do
    elapsed_ms = elapsed_us / 1000

    {count, total_us, max_us, recent} =
      Map.get(state.handler_samples, label, {0, 0, 0, :queue.new()})

    new_entry = {
      count + 1,
      total_us + elapsed_us,
      max(max_us, elapsed_us),
      queue_push(recent, elapsed_ms, @window_size)
    }

    {:noreply, %{state | handler_samples: Map.put(state.handler_samples, label, new_entry)}}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    {:reply, compute_stats(state), state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok,
     %{
       render_start: nil,
       render_times: :queue.new(),
       render_count: 0,
       render_max_ms: 0.0,
       handler_samples: %{},
       frame_timestamps: :queue.new(),
       slow_frames: 0
     }}
  end

  @impl GenServer
  def handle_info(:report, state) do
    stats = compute_stats(state)

    if stats.frame_count > 0 do
      handler_str =
        stats.handler_stats
        |> Enum.map(fn {label, h} ->
          "#{label}: avg=#{Float.round(h.avg_ms, 1)}ms max=#{Float.round(h.max_ms, 1)}ms"
        end)
        |> Enum.join(", ")

      Logger.debug(
        "[PerfMon] FPS: #{Float.round(stats.fps, 1)} (observed: #{Float.round(stats.observed_fps, 1)}) | " <>
          "render: avg=#{Float.round(stats.avg_render_ms, 1)}ms max=#{Float.round(stats.max_render_ms, 1)}ms | " <>
          "handlers: #{handler_str} | " <>
          "slow_frames: #{stats.slow_frames}/#{stats.frame_count}"
      )
    end

    Process.send_after(self(), :report, @report_interval_ms)
    {:noreply, state}
  end

  # --- Internals ---

  defp compute_stats(state) do
    render_list = :queue.to_list(state.render_times)
    avg_render = if render_list == [], do: 0.0, else: Enum.sum(render_list) / length(render_list)

    handler_stats =
      state.handler_samples
      |> Enum.map(fn {label, {count, total_us, max_us, recent}} ->
        recent_list = :queue.to_list(recent)
        avg_ms = if count > 0, do: total_us / count / 1000, else: 0.0

        recent_avg =
          if recent_list == [], do: 0.0, else: Enum.sum(recent_list) / length(recent_list)

        {label,
         %{
           count: count,
           avg_ms: avg_ms,
           max_ms: max_us / 1000,
           recent_avg_ms: recent_avg
         }}
      end)
      |> Map.new()

    fps = compute_fps(avg_render, handler_stats, state.frame_timestamps)
    observed_fps = compute_observed_fps(state.frame_timestamps)

    %{
      fps: fps,
      observed_fps: observed_fps,
      avg_render_ms: avg_render,
      max_render_ms: state.render_max_ms,
      frame_count: state.render_count,
      slow_frames: state.slow_frames,
      handler_stats: handler_stats
    }
  end

  # Scenic is event-driven: frames only render when something changes, so
  # wall-clock "frames per second" reads ~0 when the app is idle, which
  # doesn't tell you whether rendering is fast or slow. The useful metric
  # is sustainable render throughput — `1000 / frame_time_ms`. A frame's
  # cost is Scenic's GPU render (:render_times queue) plus the Elixir-side
  # graph build (:render_graph handler). This reports what FPS the pipeline
  # could hold if it rendered continuously; `observed_fps` reports actual
  # wall-clock frame cadence for debugging idleness vs slowness.
  defp compute_fps(avg_render_ms, handler_stats, frame_timestamps) do
    render_graph_ms =
      case Map.get(handler_stats, :render_graph) do
        %{avg_ms: ms} when is_number(ms) and ms > 0 -> ms
        _ -> 0.0
      end

    frame_time_ms = avg_render_ms + render_graph_ms

    cond do
      frame_time_ms > 0 -> 1000.0 / frame_time_ms
      # No render_graph samples yet — fall back to wall-clock FPS so early
      # readings (before any handler has been instrumented) still return
      # something meaningful instead of always-zero.
      true -> compute_observed_fps(frame_timestamps)
    end
  end

  defp compute_observed_fps(timestamps) do
    list = :queue.to_list(timestamps)

    case list do
      [] ->
        0.0

      [_] ->
        0.0

      _ ->
        oldest = List.first(list)
        newest = List.last(list)
        # nanoseconds to seconds
        span_s = (newest - oldest) / 1_000_000_000
        if span_s > 0, do: (length(list) - 1) / span_s, else: 0.0
    end
  end

  defp queue_push(queue, item, max_size) do
    queue = :queue.in(item, queue)

    if :queue.len(queue) > max_size do
      {_, queue} = :queue.out(queue)
      queue
    else
      queue
    end
  end
end
