defmodule Mix.Tasks.RunSpexTest do
  @moduledoc """
  Unit tests for Mix.Tasks.RunSpex.

  These tests verify the task exists, is a proper Mix task, and sets
  SCENIC_LOCAL_TARGET correctly — without actually launching the Scenic app.
  """
  use ExUnit.Case, async: false

  # Ensure Mix has loaded all tasks from the code path into its ETS registry
  # before any test in this module runs. Without this, Mix.Task.get/1 can return
  # nil even when the module is compiled, because the registry is populated lazily.
  # This mirrors what Mix does internally before executing `mix run_spex`.
  setup_all do
    Mix.Task.load_all()
    :ok
  end

  # Save and restore SCENIC_LOCAL_TARGET around each test so we don't
  # pollute the process environment across tests.
  setup do
    original = System.get_env("SCENIC_LOCAL_TARGET")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("SCENIC_LOCAL_TARGET")
        val -> System.put_env("SCENIC_LOCAL_TARGET", val)
      end
    end)

    :ok
  end

  describe "Mix.Tasks.RunSpex module" do
    test "is a valid Mix task" do
      assert function_exported?(Mix.Tasks.RunSpex, :run, 1),
             "Mix.Tasks.RunSpex must export run/1"
    end

    test "has a @shortdoc attribute mentioning spex" do
      # Module attributes are accessible via __info__(:attributes).
      # use Mix.Task stores the @shortdoc as a module attribute.
      attributes = Mix.Tasks.RunSpex.__info__(:attributes)
      shortdoc_values = Keyword.get_values(attributes, :shortdoc)

      assert shortdoc_values != [],
             "Mix.Tasks.RunSpex must have a @shortdoc attribute"

      shortdoc_text = List.first(List.flatten(shortdoc_values))
      assert is_binary(shortdoc_text), "@shortdoc must be a string"
      assert String.contains?(shortdoc_text, "spex"), "@shortdoc should mention 'spex'"
    end

    test "module is a properly defined Mix task" do
      # use Mix.Task attaches a __mix_task__ behaviour so we can verify
      # the module honours the Mix.Task contract.
      assert Code.ensure_loaded?(Mix.Tasks.RunSpex),
             "Mix.Tasks.RunSpex should be loadable"

      behaviours =
        Mix.Tasks.RunSpex.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Mix.Task in behaviours,
             "Mix.Tasks.RunSpex must implement the Mix.Task behaviour"
    end

    test "is discoverable by Mix task registry as 'run_spex'" do
      # Mix.Task.get/1 looks up the task module by name. This is the same
      # lookup Mix performs internally when you run `mix run_spex`. If it
      # returns nil, the task would show as "Unknown task run_spex" on the CLI.
      task_module = Mix.Task.get("run_spex")
      assert task_module == Mix.Tasks.RunSpex,
             "Mix.Task.get(\"run_spex\") must return Mix.Tasks.RunSpex, got: #{inspect(task_module)}"
    end

    test "declares @preferred_cli_env :test at the module level" do
      # The @preferred_cli_env module attribute ensures `mix run_spex` runs in
      # :test env even when mix.exs preferred_cli_env is not configured.
      attributes = Mix.Tasks.RunSpex.__info__(:attributes)
      preferred_env_values = Keyword.get_values(attributes, :preferred_cli_env)

      assert preferred_env_values != [],
             "Mix.Tasks.RunSpex must declare @preferred_cli_env"

      env = List.first(List.flatten(preferred_env_values))
      assert env == :test,
             "@preferred_cli_env must be :test, got: #{inspect(env)}"
    end
  end

  describe "SCENIC_LOCAL_TARGET env behaviour" do
    test "sets SCENIC_LOCAL_TARGET to glfw when not already set" do
      # Ensure the variable is absent before the test
      System.delete_env("SCENIC_LOCAL_TARGET")

      refute System.get_env("SCENIC_LOCAL_TARGET"),
             "Precondition: SCENIC_LOCAL_TARGET must not be set"

      # Call the actual module function — not a manually simulated copy.
      Mix.Tasks.RunSpex.maybe_set_scenic_target()

      assert System.get_env("SCENIC_LOCAL_TARGET") == "glfw",
             "SCENIC_LOCAL_TARGET should be set to 'glfw'"
    end

    test "does not override SCENIC_LOCAL_TARGET when already set" do
      System.put_env("SCENIC_LOCAL_TARGET", "headless")

      # Call the actual module function.
      Mix.Tasks.RunSpex.maybe_set_scenic_target()

      assert System.get_env("SCENIC_LOCAL_TARGET") == "headless",
             "Pre-existing SCENIC_LOCAL_TARGET should not be overridden"
    end

    test "maybe_set_scenic_target/0 is exported (callable without :run)" do
      assert function_exported?(Mix.Tasks.RunSpex, :maybe_set_scenic_target, 0),
             "maybe_set_scenic_target/0 must be a public function"
    end

    test "preserves any pre-existing SCENIC_LOCAL_TARGET value (not just 'headless')" do
      # The guard must work for ANY pre-existing value, not just "headless".
      for value <- ["headless", "wayland", "x11", "custom_driver"] do
        System.put_env("SCENIC_LOCAL_TARGET", value)
        Mix.Tasks.RunSpex.maybe_set_scenic_target()
        assert System.get_env("SCENIC_LOCAL_TARGET") == value,
               "Pre-existing value '#{value}' should not be overridden"
      end
    end
  end
end
