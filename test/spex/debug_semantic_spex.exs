defmodule Quillex.DebugSemanticSpex do
  @moduledoc """
  Debug test to understand why semantic queries are failing.
  """
  use SexySpex
  
  import Scenic.DevTools

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Debug Semantic Layer",
    description: "Debug why semantic queries aren't working",
    tags: [:debug] do

    scenario "Inspect semantic and scene data", context do
      given_ "Quillex is running", context do
        assert SexySpex.Helpers.application_running?(:quillex)
        Process.sleep(1000) # Give it time to fully initialize
        :ok
      end

      then_ "inspect all layers", context do
        IO.puts("\n=== RAW SEMANTIC DATA ===")
        semantic_data = raw_semantic()
        IO.inspect(semantic_data, limit: :infinity, pretty: true)
        IO.puts("\nSemantic entries: #{map_size(semantic_data)}")
        
        IO.puts("\n=== RAW SCENE SCRIPT DATA ===")
        scene_data = raw_scene_script()
        IO.puts("Scene entries: #{map_size(scene_data)}")
        
        # Check for any semantic annotations in elements
        IO.puts("\n=== ELEMENTS WITH SEMANTIC DATA ===")
        for {scene_key, scene} <- scene_data do
          for {elem_key, elem} <- scene.elements do
            if Map.has_key?(elem, :semantic) && elem.semantic != nil do
              IO.puts("\nScene: #{scene_key}, Element: #{elem_key}")
              IO.inspect(elem.semantic, pretty: true)
            end
          end
        end
        
        IO.puts("\n=== VIEWPORT INFO ===")
        case Scenic.ViewPort.info(:main_viewport) do
          {:ok, vp} -> IO.inspect(vp, pretty: true)
          error -> IO.puts("Error getting viewport: #{inspect(error)}")
        end
        
        :ok
      end
    end
  end
end