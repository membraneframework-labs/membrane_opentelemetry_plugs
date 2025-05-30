defmodule Membrane.OpenTelemetry.Plugs.Application do
  @moduledoc false
  use Application

  alias Membrane.OpenTelemetry.Plugs

  @defined_plugs [Plugs.Launch]
  @plugs_in_config Application.compile_env(:membrane_opentelemetry_plugs, :plugs, [])
  @enabled_plugs @defined_plugs |> Enum.filter(&(&1 in @plugs_in_config))

  Enum.each(@plugs_in_config, fn plug ->
    if plug not in @defined_plugs do
      IO.warn("""
      Plug #{inspect(plug)} is present in :membrane_opentelemetry_plugs config, but \
      it is not an available plug module. Available plug modules are: #{inspect(@defined_plugs)}
      """)
    end
  end)

  @impl true
  def start(_type, _args) do
    @enabled_plugs
    |> Enum.each(fn plug_module ->
      :ok = plug_module.plug()
    end)

    children = []
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    @enabled_plugs
    |> Enum.each(fn plug_module ->
      :ok = plug_module.unplug()
    end)

    :ok
  end
end
