defmodule Membrane.OpenTelemetry.Plugs.Application do
  @moduledoc false
  use Application

  alias Membrane.OpenTelemetry.Plugs

  @plugs Application.compile_env(:membrane_opentelemetry_plugs, :plugs, [])

  @impl true
  def start(_type, _args) do
    if :launch in @plugs do
      :ok = Plugs.Launch.plug()
    end

    children = []
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    if :launch in @plugs do
      :ok = Plugs.Launch.unplug()
    end

    :ok
  end
end
