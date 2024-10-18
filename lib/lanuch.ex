defmodule Membrane.OpenTelemetry.Plugs.Launch do
  @moduledoc """
  Attaches OpenTelemetry spans describing events during components launch, since `handle_init` until `handle_end_of_stream`
  """

  alias __MODULE__.{HandlerFunctions, ETSWrapper}

  @all_callbacks [
                   Membrane.Pipeline,
                   Membrane.Bin,
                   Membrane.Element.Base,
                   Membrane.Element.WithInputPads,
                   Membrane.Element.WithOutputPads
                 ]
                 |> Enum.flat_map(fn module -> module.behaviour_info(:callbacks) end)
                 |> Keyword.keys()
                 |> Enum.uniq()
                 |> List.delete(:__struct__)

  @spec plug() :: :ok
  def plug() do
    ETSWrapper.setup_ets_tables()
    attach_telemetry_handlers()
    :ok
  end

  @spec unplug() :: :ok
  def unplug() do
    detach_telemetry_handlers()
    ETSWrapper.delete_ets_tables()
    :ok
  end

  defp attach_telemetry_handlers() do
    :ok =
      :telemetry.attach(
        {__MODULE__, :start_span},
        [:membrane, :handle_init, :start],
        &HandlerFunctions.start_span/4,
        nil
      )

    @all_callbacks
    |> Enum.each(fn callback ->
      :ok =
        :telemetry.attach(
          {__MODULE__, callback, :start},
          [:membrane, callback, :start],
          &HandlerFunctions.callback_start/4,
          nil
        )

      :ok =
        :telemetry.attach(
          {__MODULE__, callback, :stop},
          [:membrane, callback, :stop],
          &HandlerFunctions.callback_stop/4,
          nil
        )
    end)

    :ok =
      :telemetry.attach(
        {__MODULE__, :maybe_end_span_on_start_of_stream},
        [:membrane, :handle_start_of_stream, :stop],
        &HandlerFunctions.maybe_end_span/4,
        nil
      )

    :ok =
      :telemetry.attach(
        {__MODULE__, :maybe_end_span_on_playing},
        [:membrane, :handle_playing, :stop],
        &HandlerFunctions.maybe_end_span/4,
        nil
      )
  end

  defp detach_telemetry_handlers() do
    @all_callbacks
    |> Enum.flat_map(fn callback ->
      [
        {__MODULE__, callback, :start},
        {__MODULE__, callback, :stop}
      ]
    end)
    |> Enum.concat([
      {__MODULE__, :start_span},
      {__MODULE__, :end_element_span},
      {__MODULE__, :end_parent_span}
    ])
    |> Enum.each(fn handler_id ->
      :ok = :telemetry.detach(handler_id)
    end)
  end
end
