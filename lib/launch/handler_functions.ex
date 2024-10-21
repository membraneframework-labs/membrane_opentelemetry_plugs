defmodule Membrane.OpenTelemetry.Plugs.Launch.HandlerFunctions do
  @moduledoc false
  require Membrane.OpenTelemetry
  require Membrane.Logger

  alias Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper

  # @span_id "membrane_component_launch"
  # @pdict_key_span_alive? :__membrane_opentelemetry_lanuch_span_alive?
  @pdict_span_id_key :__membrane_opentelemetry_launch_span_name__

  @spec start_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def start_span(_name, _measurements, metadata, _config) do
    metadata.component_state.module.membrane_component_type()
    |> do_start_span(metadata.component_state)

    :ok
  end

  defp do_start_span(component_type, component_state)

  defp do_start_span(:pipeline, component_state) do
    # Membrane.OpenTelemetry.start_span(@span_id)
    # Process.put(@pdict_key_span_alive?, true)
    span_id = get_span_id(component_state)
    Process.put(@pdict_span_id_key, span_id)

    Membrane.OpenTelemetry.start_span(span_id)

    pipeline = self()

    Membrane.OpenTelemetry.get_span(span_id)
    |> ETSWrapper.store_span_and_pipeline(pipeline)

    ETSWrapper.store_pipeline_offspring(pipeline)
    set_span_attributes(component_state)

    Task.start(__MODULE__, :pipeline_monitor, [pipeline])
  end

  defp do_start_span(:bin, component_state) do
    {:ok, parent_span_ctx, pipeline} =
      ETSWrapper.get_span_and_pipeline(component_state.parent_pid)

    span_id = get_span_id(component_state)
    Process.put(@pdict_span_id_key, span_id)

    Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span_ctx)
    # Process.put(@pdict_key_span_alive?, true)

    Membrane.OpenTelemetry.get_span(span_id)
    |> ETSWrapper.store_span_and_pipeline(pipeline)

    ETSWrapper.store_pipeline_offspring(pipeline)
    set_span_attributes(component_state)
  end

  defp do_start_span(:element, component_state) do
    {:ok, parent_span_ctx, _pipeline} =
      ETSWrapper.get_span_and_pipeline(component_state.parent_pid)

    span_id = get_span_id(component_state)
    Process.put(@pdict_span_id_key, span_id)

    Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span_ctx)
    # Process.put(@pdict_key_span_alive?, true)
    set_span_attributes(component_state)
  end

  @spec maybe_end_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def maybe_end_span([:membrane, callback, :stop], _mesaurements, metadata, _config) do
    type = get_type(metadata.component_state)

    case callback do
      :handle_playing when type in [:source, :bin, :pipeline] ->
        do_end_span()

      :handle_playing when type in [:filter, :endpoint, :sink] ->
        :ok

      :handle_start_of_stream when type in [:filter, :endpoint, :sink] ->
        do_end_span()

      :handle_start_of_stream when type in [:source, :bin, :pipeline] ->
        :ok
    end
  end

  @spec ensure_span_ended() :: :ok
  def ensure_span_ended(), do: do_end_span()

  defp do_end_span() do
    with span_id when span_id != nil <- Process.delete(@pdict_span_id_key) do
      Membrane.OpenTelemetry.end_span(span_id)
    end

    :ok
  end

  @spec callback_start(:telemetry.event_name(), map(), map(), any()) :: :ok
  def callback_start([:membrane, _callback, :start] = name, _measurements, _metadata, _config) do
    # if Process.get(@pdict_key_span_alive?, false) do
    #   event_name = name |> Enum.map_join("_", &Atom.to_string/1)
    #   Membrane.OpenTelemetry.add_event(@span_id, event_name)
    # end

    with span_id when span_id != nil <- Process.get(@pdict_span_id_key) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      Membrane.OpenTelemetry.add_event(span_id, event_name)
    end

    :ok
  end

  @spec callback_stop(:telemetry.event_name(), map(), map(), any()) :: :ok
  def callback_stop(
        [:membrane, _callback, :stop] = name,
        %{duration: duration},
        _metadata,
        _config
      ) do
    # if Process.get(@pdict_key_span_alive?, false) do
    #   event_name = name |> Enum.map_join("_", &Atom.to_string/1)
    #   Membrane.OpenTelemetry.add_event(@span_id, event_name, duration: duration)
    # end

    with span_id when span_id != nil <- Process.get(@pdict_span_id_key) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      Membrane.OpenTelemetry.add_event(span_id, event_name, duration: duration)
    end

    :ok
  end

  @spec pipeline_monitor(pid()) :: :ok
  def pipeline_monitor(pipeline) do
    ref = Process.monitor(pipeline)

    receive do
      {:DOWN, ^ref, _process, _pid, _reason} -> cleanup_pipeline(pipeline)
    end

    :ok
  end

  defp cleanup_pipeline(pipeline) do
    ETSWrapper.get_pipeline_offsprings(pipeline)
    |> Enum.each(fn offspring ->
      {:ok, span_ctx, ^pipeline} = ETSWrapper.get_span_and_pipeline(offspring)
      ETSWrapper.delete_span_and_pipeline(offspring, span_ctx, pipeline)
      ETSWrapper.delete_pipeline_offspring(pipeline, offspring)
    end)
  end

  defp set_span_attributes(component_state) do
    with span_id when span_id != nil <- Process.get(@pdict_span_id_key) do
      type = component_state.module.membrane_component_type() |> inspect()
      Membrane.OpenTelemetry.set_attribute(span_id, :component_type, type)

      name =
        case component_state do
          %{name: name} when name != nil -> inspect(name)
          %{} -> "#{String.capitalize(type)} #{self() |> inspect()}"
        end

      Membrane.OpenTelemetry.set_attribute(span_id, :component_name, name)

      module = component_state.module |> inspect()
      Membrane.OpenTelemetry.set_attribute(span_id, :component_module, module)
    end

    :ok
  end

  defp get_span_id(component_state) do
    "membrane_#{get_type(component_state)}_launch_#{inspect(component_state.module)}"
  end

  defp get_type(component_state) do
    case component_state.module.membrane_component_type() do
      :element -> component_state.module.membrane_element_type()
      :bin -> :bin
      :pipeline -> :pipeline
    end
  end
end
