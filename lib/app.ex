defmodule QuillEx.App do
  @moduledoc """
  Boots and supervises the processes owned by the Quillex OTP application.

  This module is the application callback configured in `mix.exs`. Its
  `start/2` callback resolves runtime ownership, applies standalone CLI policy,
  constructs the appropriate child list, appends optional development tooling,
  and starts the children under a `:one_for_one` supervisor.

  ## Runtime modes

  The mode is read from the `:quillex` application's `:runtime_mode` setting:

      config :quillex, runtime_mode: :standalone

  `:standalone` is the default and is the complete desktop application. Quillex
  adopts the directory supplied by its command-line launcher, starts performance
  monitoring, the RadixCache stores, buffer supervision, close-lifecycle and CLI
  services, and Scenic with Quillex's own window and root scene. Quillex owns the
  viewport and decides when its standalone runtime should stop.

  `:embedded` starts the RadixCache and buffer backends for use inside another
  application. The host retains its process-wide working directory, owns Scenic,
  supplies any viewport or editing surface, and controls VM/application lifetime.
  Quillex therefore does not start its CLI, performance monitor, lifecycle
  coordinator, or standalone Scenic window in this mode.

  `:headless` starts the same backend child set as `:embedded` today, but states a
  different contract: there is no graphical host or Quillex viewport. Callers
  work through the `Quillex.Buffer` API and its `Quillex.Buffer.Ref` and
  `Quillex.Buffer.Snapshot` read contracts. Keeping this mode distinct from
  `:embedded` allows their supervision needs to evolve independently even though
  their current child lists are identical.

  In development, the optional Tidewave/Bandit child is appended to any mode
  when those modules are available; it is development tooling rather than part
  of a mode's product ownership contract. Unknown mode values raise
  `ArgumentError` during application startup.
  """

  @tidewave_port 31337
  @start_tidewave? Mix.env() == :dev and Code.ensure_loaded?(Tidewave) and
                     Code.ensure_loaded?(Bandit)

  def start(_type, _args) do
    mode = runtime_mode()

    # Working-directory adoption is standalone shell policy. Embedded and
    # headless hosts retain ownership of their process-wide current directory.
    if mode == :standalone, do: QuillEx.CLI.chdir!()

    children = children_for(mode)

    children =
      children ++
        if @start_tidewave? do
          require Logger
          Logger.info("Starting Tidewave server on port #{@tidewave_port} for development")
          [{Bandit, plug: Tidewave, port: @tidewave_port}]
        else
          []
        end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc "Return the generic Quillex runtime mode."
  @spec runtime_mode() :: :standalone | :embedded | :headless
  def runtime_mode do
    case Application.get_env(:quillex, :runtime_mode, :standalone) do
      mode when mode in [:standalone, :embedded, :headless] -> mode
      mode -> raise ArgumentError, "invalid Quillex runtime mode: #{inspect(mode)}"
    end
  end

  @doc false
  def children_for(:standalone) do
    [
      {Quillex.PerfMonitor, []},
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []},
      {Quillex.Files.ExternalFileSync, []},
      {Quillex.Lifecycle.Coordinator, []},
      {QuillEx.CLI, []},
      {Scenic, [scenic_config()]}
    ]
  end

  def children_for(:embedded) do
    [
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []},
      {Quillex.Files.ExternalFileSync, []}
    ]
  end

  def children_for(:headless) do
    [
      {Quillex.RadixCache.Supervisor, []},
      {Quillex.Buffers.TopSupervisor, []},
      {Quillex.Files.ExternalFileSync, []}
    ]
  end

  @window_title if Mix.env() == :test, do: "Quillex (test)", else: "Quillex"
  @default_resolution {1680, 1005}

  # Resolved at compile time, deliberately: Mix does not exist inside a release,
  # so asking Mix.env() while the app is booting would crash the packaged app.
  @test_env? Mix.env() == :test

  def scenic_config() do
    window_size = window_size()

    [
      name: :main_viewport,
      size: window_size,
      default_scene: {QuillEx.RootScene, []},
      drivers: [
        # valid options are: [:name, :limit_ms, :layer, :opacity, :debug, :antialias, :calibration, :position, :window, :cursor, :key_map, :on_close]
        [
          name: :scenic_driver,
          module: Scenic.Driver.Local,
          window: [
            title: @window_title,
            resizeable: true
          ],
          debug: true,
          on_close: {__MODULE__, :request_close, []}
          # limit_ms: 500
        ]
      ]
    ]
  end

  @doc false
  def request_close(reason) do
    Quillex.Lifecycle.Coordinator.request_close(reason)
    :defer
  end

  # Force a wider window under test so text doesn't wrap mid-assertion.
  defp window_size do
    if @test_env? do
      {2000, 1200}
    else
      Application.get_env(:quillex, :test_window_size, @default_resolution)
    end
  end
end
