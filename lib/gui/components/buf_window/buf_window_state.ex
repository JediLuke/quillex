# The idea is that the component may actually have different state
# to the Buffer, e.g. `mode` is really just a GUI centric concept,
# not a buffer-centric one

#   defstruct [
#     # affects how we render the cursor
#     mode: nil,
#     # the font settings for this TextPad
#     font: nil,
#     # hold the list of LineOfText structs
#     lines: nil,
#     # how much margin we want to leave around the edges
#     margin: nil,
#     # maintains the cursor coords, note we just support single-cursor for now
#     cursor: %{
#       line: nil,
#       col: nil
#     },
#     opts: %{
#       alignment: :left,
#       wrap: :no_wrap,
#       scroll: %{
#         direction: :all,
#         # An accumulator for the amount of scroll
#         acc: {0, 0}
#       },
#       # toggles the display of line numbers in the left margin
#       show_line_nums?: false
#     }
#   ]
