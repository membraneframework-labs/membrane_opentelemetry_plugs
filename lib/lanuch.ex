defmodule Membrane.OpenTelemetry.Plugs.Launch do
  @moduledoc """
  Attaches OpenTelemetry spans describing events during launch of the component.
  Each span starts when the `handle_init` callback is invoked and lasts until the `handle_start_of_stream` invocation ends.
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
    # attach_telemetry_handlers()
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
      attach(
        :start_span,
        :handle_init,
        :start,
        &HandlerFunctions.start_span/4
      )

    @all_callbacks
    |> Enum.each(fn callback ->
      :ok =
        attach(
          {callback, :start},
          callback,
          :start,
          &HandlerFunctions.callback_start/4
        )

      :ok =
        attach(
          {callback, :stop},
          callback,
          :stop,
          &HandlerFunctions.callback_stop/4
        )
    end)

    :ok =
      attach(
        :maybe_end_span_on_start_of_stream,
        :handle_start_of_stream,
        :stop,
        &HandlerFunctions.ensure_span_ended/4
      )

    :ok =
      attach(
        :maybe_end_span_on_playing,
        :handle_playing,
        :stop,
        &HandlerFunctions.maybe_end_span/4
      )
  end

  defp attach(id, callback, start_or_stop, handler) do
    [:pipeline, :bin, :element]
    |> Enum.each(fn component_type ->
      :telemetry.attach(
        {__MODULE__, component_type, id},
        [:membrane, component_type, callback, start_or_stop],
        handler,
        nil
      )
    end)
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
      {__MODULE__, :maybe_end_span_on_start_of_stream},
      {__MODULE__, :maybe_end_span_on_playing}
    ])
    |> Enum.each(fn handler_id ->
      :ok = :telemetry.detach(handler_id)
    end)
  end
end
