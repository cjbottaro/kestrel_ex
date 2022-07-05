defmodule Kestrel.OtpAppCache do
  @moduledoc false
  use Agent

  def start_link(_config) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(module) do
    Agent.get_and_update(__MODULE__, fn cache ->
      case cache[module] do
        nil ->
          otp_app = Application.get_application(module)
          cache = Map.put(cache, module, otp_app)
          {otp_app, cache}

        otp_app -> {otp_app, cache}
      end
    end)
  end

end
