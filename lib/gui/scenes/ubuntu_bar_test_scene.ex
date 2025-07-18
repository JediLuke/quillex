# defmodule QuillEx.UbuntuBarTestScene do
#   @moduledoc """
#   Test scene for systematically testing all Ubuntu bar configurations.
#   This scene cycles through all combinations of layouts and button sets.
#   """
#   use Scenic.Scene
#   require Logger
#   alias Scenic.Graph
#   alias Scenic.Scene
#   import Scenic.Primitives

#   # Test configurations
#   @layouts [:top, :center, :bottom]
#   @button_sets [
#     {:ascii, ScenicWidgets.UbuntuBar.ascii_buttons()},
#     {:emoji, ScenicWidgets.UbuntuBar.emoji_buttons()},
#     {:egyptian, ScenicWidgets.UbuntuBar.egyptian_buttons()},
#     {:symbol, ScenicWidgets.UbuntuBar.symbol_buttons()}
#   ]
#   
#   # Test cycle timing
#   @cycle_delay 3000  # 3 seconds per configuration

#   def init(scene, _args, _opts) do
#     # Start with first configuration
#     state = %{
#       current_layout_index: 0,
#       current_button_set_index: 0,
#       test_results: [],
#       frame: %{
#         size: %{width: 60, height: scene.viewport.size.height}
#       }
#     }
#     
#     # Schedule first update
#     Process.send_after(self(), :next_config, 100)
#     
#     # Initial render
#     graph = render_test_config(Graph.build(), state)
#     
#     scene = scene
#     |> assign(state: state)
#     |> push_graph(graph)
#     
#     {:ok, scene}
#   end
#   
#   def handle_info(:next_config, scene) do
#     state = scene.assigns.state
#     
#     # Current configuration
#     layout = Enum.at(@layouts, state.current_layout_index)
#     {button_set_name, buttons} = Enum.at(@button_sets, state.current_button_set_index)
#     
#     # Log current test
#     config_name = "#{layout}_#{button_set_name}"
#     Logger.info("Testing Ubuntu bar: #{config_name}")
#     
#     # Request screenshot capture
#     send(self(), {:capture_screenshot, config_name})
#     
#     # Calculate next indices
#     {next_layout_idx, next_button_idx} = 
#       if state.current_button_set_index + 1 >= length(@button_sets) do
#         # Move to next layout
#         if state.current_layout_index + 1 >= length(@layouts) do
#           # All tests complete!
#           send(self(), :tests_complete)
#           {state.current_layout_index, state.current_button_set_index}
#         else
#           {state.current_layout_index + 1, 0}
#         end
#       else
#         {state.current_layout_index, state.current_button_set_index + 1}
#       end
#     
#     # Update state
#     new_state = %{state | 
#       current_layout_index: next_layout_idx,
#       current_button_set_index: next_button_idx
#     }
#     
#     # Render new configuration
#     graph = render_test_config(scene.assigns.graph, new_state)
#     
#     scene = scene
#     |> assign(state: new_state)
#     |> push_graph(graph)
#     
#     # Schedule next update (unless complete)
#     unless next_layout_idx == state.current_layout_index && 
#            next_button_idx == state.current_button_set_index do
#       Process.send_after(self(), :next_config, @cycle_delay)
#     end
#     
#     {:noreply, scene}
#   end
#   
#   def handle_info({:capture_screenshot, config_name}, scene) do
#     # In a real test, we'd trigger screenshot capture here
#     # For now, just log that we would capture
#     timestamp = DateTime.utc_now() |> DateTime.to_string()
#     result = %{
#       config: config_name,
#       timestamp: timestamp,
#       screenshot_path: "/tmp/ubuntu_bar_test_#{config_name}_#{:os.system_time(:millisecond)}.png"
#     }
#     
#     new_state = %{scene.assigns.state | 
#       test_results: scene.assigns.state.test_results ++ [result]
#     }
#     
#     {:noreply, assign(scene, state: new_state)}
#   end
#   
#   def handle_info(:tests_complete, scene) do
#     Logger.info("=== Ubuntu Bar Test Results ===")
#     Enum.each(scene.assigns.state.test_results, fn result ->
#       Logger.info("Config: #{result.config} - Screenshot: #{result.screenshot_path}")
#     end)
#     Logger.info("=== Tests Complete ===")
#     
#     # Generate summary report
#     generate_test_report(scene.assigns.state.test_results)
#     
#     {:noreply, scene}
#   end
#   
#   def handle_info({:ubuntu_bar_button_clicked, button_id, button}, scene) do
#     Logger.info("Test scene received button click: #{inspect(button_id)} - #{inspect(button)}")
#     {:noreply, scene}
#   end
#   
#   defp render_test_config(graph, state) do
#     layout = Enum.at(@layouts, state.current_layout_index)
#     {button_set_name, buttons} = Enum.at(@button_sets, state.current_button_set_index)
#     
#     # Clear graph
#     graph = Graph.build()
#     
#     # Draw background
#     graph = graph
#     |> rect({state.frame.size.width, state.frame.size.height}, 
#         fill: {30, 30, 30})
#     
#     # Add Ubuntu bar with current configuration
#     ubuntu_bar_data = %{
#       buttons: buttons,
#       layout: layout,
#       button_size: 48,
#       button_spacing: 10,
#       background_color: {40, 40, 40},
#       button_color: {55, 55, 55},
#       button_hover_color: {75, 75, 75},
#       button_active_color: {85, 130, 180},
#       text_color: {240, 240, 240},
#       font_size: 18
#       # font_family: case button_set_name do
#       #   :egyptian -> QuillEx.Utils.SafeFontLoader.get_hieroglyph_font()  # TODO: Add hieroglyph fonts
#       #   :symbol -> QuillEx.Utils.SafeFontLoader.get_symbol_font()        # TODO: Add symbol fonts
#       #   _ -> nil
#       # end
#     }
#     
#     graph
#     |> ScenicWidgets.UbuntuBar.add_to_graph(
#       ubuntu_bar_data,
#       id: :test_ubuntu_bar,
#       frame: state.frame
#     )
#     
#     # Add test info overlay
#     |> text("Layout: #{layout}", 
#         translate: {70, 20}, 
#         fill: :white,
#         font_size: 14)
#     |> text("Buttons: #{button_set_name}", 
#         translate: {70, 40}, 
#         fill: :white,
#         font_size: 14)
#   end
#   
#   defp generate_test_report(results) do
#     report = """
#     # Ubuntu Bar Component Test Report
#     
#     ## Test Matrix Results
#     
#     Total configurations tested: #{length(results)}
#     
#     | Layout | Button Set | Screenshot | Timestamp |
#     |--------|-----------|------------|-----------|
#     """ <>
#     Enum.map_join(results, "\n", fn r ->
#       [layout, buttons] = String.split(r.config, "_")
#       "| #{layout} | #{buttons} | #{Path.basename(r.screenshot_path)} | #{r.timestamp} |"
#     end)
#     
#     # Write report to file
#     File.write!("/tmp/ubuntu_bar_test_report.md", report)
#     Logger.info("Test report written to: /tmp/ubuntu_bar_test_report.md")
#   end
# end