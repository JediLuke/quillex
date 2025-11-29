# Configure Quillex to use :edit mode for spex tests (notepad-style editing)
Application.put_env(:quillex, :default_buffer_mode, :edit)

ExUnit.start()
