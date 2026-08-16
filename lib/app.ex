defmodule QuillEx.App do
	@moduledoc """
	Boots the supervision tree for the Quillex OTP application.
	
	This module is the application callback configured in `mix.exs`. Its
	`start/2` callback resolves runtime ownership, applies standalone CLI policy,
	constructs the selected child list and starts the children under a `:one_for_one` supervisor.

	## Runtime modes

	The mode is read from the `:quillex` application's `:runtime_mode` setting:

		config :quillex, runtime_mode: :standalone

	`:standalone` is the default and is the complete desktop application. Quillex
	adopts the directory supplied by its command-line launcher, starts performance
	monitoring, the RadixCache stores, buffer supervision, close-lifecycle and CLI
	services, and Scenic with Quillex's own window and root scene. Quillex owns the
	viewport and decides when its standalone runtime should stop.

	`:headless` starts Quillex's RadixCache and buffer backends without starting
	its desktop shell. The caller retains the process-wide working directory,
	owns VM/application lifetime, and may either use `Quillex.Buffer` directly or
	compose Quillex-backed UI into a host application. Quillex does not start its
	CLI, performance monitor, lifecycle coordinator, or Scenic viewport in this
	mode.

	Unknown mode values raise `ArgumentError` during application startup.
	"""

	def start(_type, _args) do
		mode = runtime_mode()

		# Working-directory adoption is standalone shell policy. Headless hosts
		# retain ownership of their process-wide current directory.
		if mode == :standalone, do: QuillEx.CLI.chdir!()

		Supervisor.start_link(children_for(mode), strategy: :one_for_one)
	end

	@doc "Return the generic Quillex runtime mode."
	@spec runtime_mode() :: :standalone | :headless
	def runtime_mode do
		case Application.get_env(:quillex, :runtime_mode, :standalone) do
			mode when mode in [:standalone, :headless] -> mode
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
			{Quillex.Files.NavigatorTreeSync, []},
			{Quillex.Lifecycle.Coordinator, []},
			{QuillEx.CLI, []},
			{Scenic, [scenic_config()]}
		]
	end

	def children_for(:headless) do
		[
			{Quillex.RadixCache.Supervisor, []},
			{Quillex.Buffers.TopSupervisor, []},
			{Quillex.Files.ExternalFileSync, []},
			{Quillex.Files.NavigatorTreeSync, []}
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
