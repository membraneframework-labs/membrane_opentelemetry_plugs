defmodule Membrane.OpenTelemetry.Plugs.Launch.HandlerFunctions do
  @moduledoc false
  require Membrane.OpenTelemetry
  require Membrane.Logger

  alias Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper

  @span_id "component_launch"
  @pdict_key_span_alive? :__membrane_opentelemetry_lanuch_span_alive?

  @spec start_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def start_span(_name, _measurements, metadata, _config) do
    metadata.component_state.module.membrane_component_type()
    |> do_start_span(metadata.component_state)

    :ok
  end

  defp do_start_span(component_type, component_state)

  defp do_start_span(:pipeline, component_state) do
    Membrane.OpenTelemetry.start_span(@span_id)
    Process.put(@pdict_key_span_alive?, true)

    pipeline = self()

    Membrane.OpenTelemetry.get_span(@span_id)
    |> ETSWrapper.store_span_and_pipeline(pipeline)

    ETSWrapper.store_pipeline_offspring(pipeline)
    set_span_attributes(component_state)

    Task.start(__MODULE__, :pipeline_monitor, [pipeline])
  end

  defp do_start_span(:bin, component_state) do
    {:ok, parent_span_ctx, pipeline} =
      ETSWrapper.get_span_and_pipeline(component_state.parent_pid)

    Membrane.OpenTelemetry.start_span(@span_id, parent_span: parent_span_ctx)
    Process.put(@pdict_key_span_alive?, true)

    Membrane.OpenTelemetry.get_span(@span_id)
    |> ETSWrapper.store_span_and_pipeline(pipeline)

    ETSWrapper.store_pipeline_offspring(pipeline)
    set_span_attributes(component_state)
  end

  defp do_start_span(:element, component_state) do
    {:ok, parent_span_ctx, _pipeline} =
      ETSWrapper.get_span_and_pipeline(component_state.parent_pid)

    Membrane.OpenTelemetry.start_span(@span_id, parent_span: parent_span_ctx)
    Process.put(@pdict_key_span_alive?, true)
    set_span_attributes(component_state)
  end

  @spec maybe_end_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def maybe_end_span([:membrane, callback, :stop], _mesaurements, metadata, _config) do
    component_module = metadata.component_state.module

    type =
      case component_module.membrane_component_type() do
        :element -> component_module.membrane_element_type()
        :bin -> :bin
        :pipeline -> :pipeline
      end

    case callback do
      :handle_playing when type in [:source, :bin, :pipeline] ->
        do_end_span(metadata.component_state)

      :handle_playing ->
        :ok

      :handle_start_of_stream when type in [:filter, :endpoint, :sink] ->
        do_end_span(metadata.component_state)

      :handle_start_of_stream ->
        :ok
    end
  end

  defp do_end_span(state) do
    type = state.module.membrane_component_type() |> inspect()
    module = state.module |> inspect()

    "END SPAN #{type} #{module}"
    |> Membrane.Logger.warning()

    if Process.get(@pdict_key_span_alive?, false) do
      Membrane.OpenTelemetry.end_span(@span_id)
      Process.put(@pdict_key_span_alive?, false)
    end

    :ok
  end

  @spec callback_start(:telemetry.event_name(), map(), map(), any()) :: :ok
  def callback_start([:membrane, _callback, :start] = name, _measurements, _metadata, _config) do
    if Process.get(@pdict_key_span_alive?, false) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      Membrane.OpenTelemetry.add_event(@span_id, event_name)
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
    if Process.get(@pdict_key_span_alive?, false) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      Membrane.OpenTelemetry.add_event(@span_id, event_name, duration: duration)
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
    name =
      case component_state do
        %{name: name} -> name |> inspect()
        %{} -> "Pipeline #{self() |> inspect()}"
      end

    Membrane.OpenTelemetry.set_attribute(@span_id, :component_name, name)

    type = component_state.module.membrane_component_type() |> inspect()
    Membrane.OpenTelemetry.set_attribute(@span_id, :component_type, type)

    module = component_state.module |> inspect()
    Membrane.OpenTelemetry.set_attribute(@span_id, :component_module, module)

    "SET SPAN ATTRIBUTES #{type} #{module} #{name}"
    |> Membrane.Logger.warning()
  end
end
