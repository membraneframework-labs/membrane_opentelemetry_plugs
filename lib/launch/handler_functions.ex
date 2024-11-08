defmodule Membrane.OpenTelemetry.Plugs.Launch.HandlerFunctions do
  @moduledoc false
  require Membrane.OpenTelemetry
  require Membrane.Logger

  alias Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper

  @tracked_pipelines Application.compile_env(
                       :membrane_opentelemetry_plugs,
                       :tracked_pipelines,
                       :all
                     )
  @pdict_span_id_key :__membrane_opentelemetry_launch_span_name__

  @spec tracked_pipelines() :: atom() | [module()]
  def tracked_pipelines(), do: @tracked_pipelines

  @spec start_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def start_span(_name, _measurements, metadata, _config) do
    metadata.component_state.module.membrane_component_type()
    |> do_start_span(metadata.component_state)

    :ok
  end

  defp do_start_span(component_type, component_state)

  defp do_start_span(:pipeline, component_state) do
    # trick to mute dialyzer
    tracked_pipelines = apply(__MODULE__, :tracked_pipelines, [])

    if tracked_pipelines == :all or component_state.module in tracked_pipelines do
      span_id = get_span_id(:pipeline, component_state)
      Process.put(@pdict_span_id_key, span_id)

      Membrane.OpenTelemetry.start_span(span_id)

      pipeline = self()

      Membrane.OpenTelemetry.get_span(span_id)
      |> ETSWrapper.store_span_and_pipeline(pipeline)

      ETSWrapper.store_as_parent_within_pipeline(pipeline)
      set_span_attributes(component_state)

      Task.start(__MODULE__, :pipeline_monitor, [pipeline])
    end
  end

  defp do_start_span(:bin, component_state) do
    with {:ok, parent_span_ctx, pipeline} <-
           ETSWrapper.get_span_and_pipeline(component_state.parent_pid) do
      span_id = get_span_id(:bin, component_state)
      Process.put(@pdict_span_id_key, span_id)

      Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span_ctx)

      Membrane.OpenTelemetry.get_span(span_id)
      |> ETSWrapper.store_span_and_pipeline(pipeline)

      ETSWrapper.store_as_parent_within_pipeline(pipeline)
      set_span_attributes(component_state)
    end
  end

  defp do_start_span(:element, component_state) do
    with {:ok, parent_span_ctx, _pipeline} <-
           ETSWrapper.get_span_and_pipeline(component_state.parent_pid) do
      span_id = get_span_id(:element, component_state)
      Process.put(@pdict_span_id_key, span_id)

      Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span_ctx)
      set_span_attributes(component_state)
    end
  end

  @spec ensure_span_ended(:telemetry.event_name(), map(), map(), any()) :: :ok
  def ensure_span_ended(
        [:membrane, :handle_start_of_stream, :stop],
        _mesaurements,
        _metadata,
        _config
      ) do
    do_ensure_span_ended()
    :ok
  end

  @spec maybe_end_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def maybe_end_span([:membrane, :handle_playing, :stop], _mesaurements, metadata, _config) do
    component_state = metadata.component_state

    if get_type(component_state) in [:source, :bin, :pipeline] or
         Enum.all?(component_state.pads_data, fn {_pad, data} -> data.direction == :output end) do
      do_ensure_span_ended()
    end

    :ok
  end

  defp do_ensure_span_ended() do
    with span_id when span_id != nil <- Process.delete(@pdict_span_id_key) do
      Membrane.OpenTelemetry.end_span(span_id)
    end
  end

  @spec callback_start(:telemetry.event_name(), map(), map(), any()) :: :ok
  def callback_start([:membrane, callback, :start] = name, _measurements, metadata, _config) do
    with span_id when span_id != nil <- Process.get(@pdict_span_id_key) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      event_attributes = get_callback_attributes(callback, metadata.callback_args)
      Membrane.OpenTelemetry.add_event(span_id, event_name, event_attributes)
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
    ETSWrapper.get_parents_within_pipeline(pipeline)
    |> Enum.each(fn parent ->
      {:ok, span_ctx, ^pipeline} = ETSWrapper.get_span_and_pipeline(parent)
      ETSWrapper.delete_span_and_pipeline(parent, span_ctx, pipeline)
      ETSWrapper.delete_parent_within_pipeline(pipeline, parent)
    end)
  end

  defp set_span_attributes(component_state) do
    with span_id when span_id != nil <- Process.get(@pdict_span_id_key) do
      type = component_state.module.membrane_component_type() |> inspect()
      Membrane.OpenTelemetry.set_attribute(span_id, :component_type, type)

      name = get_pretty_name(component_state)
      Membrane.OpenTelemetry.set_attribute(span_id, :component_name, name)

      module = component_state.module |> inspect()
      Membrane.OpenTelemetry.set_attribute(span_id, :component_module, module)
    end

    :ok
  end

  defp get_callback_attributes(callback, callback_args) do
    case callback do
      :handle_parent_notification -> [:notification]
      :handle_child_notification -> [:notification, :child]
      :handle_event -> [:pad, :event]
      :handle_stream_format -> [:pad, :stream_format]
      :handle_info -> [:message]
      _rest -> []
    end
    |> Enum.zip(callback_args)
    |> Enum.map(fn {key, value} -> {key, inspect(value)} end)
  end

  defp get_span_id(:pipeline, component_state) do
    "membrane_pipeline_launch_#{inspect(component_state.module)}"
  end

  defp get_span_id(_bin_or_element, component_state) do
    "membrane_#{get_type(component_state)}_launch_#{get_pretty_name(component_state)}"
  end

  defp get_pretty_name(component_state) do
    type = get_type(component_state)

    case component_state do
      %{name: name} when is_binary(name) -> name
      %{name: name} when name != nil -> inspect(name)
      %{} -> "#{Atom.to_string(type) |> String.capitalize()} #{self() |> inspect()}"
    end
  end

  defp get_type(component_state) do
    case component_state.module.membrane_component_type() do
      :element -> component_state.module.membrane_element_type()
      :bin -> :bin
      :pipeline -> :pipeline
    end
  end
end
