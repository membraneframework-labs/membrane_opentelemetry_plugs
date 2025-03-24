defmodule Membrane.OpenTelemetry.Plugs.Launch.HandlerFunctions do
  @moduledoc false
  require Membrane.OpenTelemetry
  require Membrane.Logger

  alias ElixirSense.Log
  alias Membrane.ComponentPath
  alias Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper

  @tracked_pipelines Application.compile_env(
                       :membrane_opentelemetry_plugs,
                       :tracked_pipelines,
                       :all
                     )
  @pdict_launch_span_id_key :__membrane_opentelemetry_launch_span_name__

  @spec tracked_pipelines() :: atom() | [module()]
  def tracked_pipelines(), do: @tracked_pipelines

  @spec start_span(
          :telemetry.event_name(),
          measurements :: map(),
          metadata :: Membrane.Telemetry.callback_span_metadata(),
          config :: any()
        ) :: :ok
  def start_span(_name, _measurements, metadata, _config) do
    do_start_span(metadata)
    :ok
  end

  @spec do_start_span(Membrane.Telemetry.callback_span_metadata()) :: any()
  defp do_start_span(metadata)

  defp do_start_span(%{component_type: :pipeline} = metadata) do
    # trick to mute dialyzer
    # tracked_pipelines = apply(__MODULE__, :tracked_pipelines, [])
    #
    # if tracked_pipelines == :all or metadata.callback_context.module in tracked_pipelines do
    #   span_id = get_launch_span_id(metadata)
    #   Process.put(@pdict_launch_span_id_key, span_id)
    #
    #   # Membrane.OpenTelemetry.start_span(span_id)
    #   start_span_log(span_id)
    #
    #   pipeline_path = ComponentPath.get()
    #
    #   # span = Membrane.OpenTelemetry.get_span(span_id)
    #   # ETSWrapper.store_span(pipeline_path, span)
    #   ETSWrapper.store_span(pipeline_path, nil)
    #
    #   ETSWrapper.store_as_parent_within_pipeline(pipeline_path, pipeline_path)
    #   set_launch_span_attributes(metadata)
    #
    #   start_init_to_playing_span(metadata)
    #
    #   Task.start(__MODULE__, :pipeline_monitor, [self(), pipeline_path])
    # end
  end

  defp do_start_span(%{component_type: :bin} = metadata) do
    # with {:ok, parent_span} <-
    #        get_parent_component_path() |> ETSWrapper.get_span() do
    #   span_id = get_launch_span_id(metadata)
    #   Process.put(@pdict_launch_span_id_key, span_id)
    #
    #   # Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span)
    #   start_span_log(span_id)
    #
    #   # span = Membrane.OpenTelemetry.get_span(span_id)
    #
    #   [pipeline_name | _tail] = my_path = ComponentPath.get()
    #
    #   # ETSWrapper.store_span(my_path, span)
    #   ETSWrapper.store_span(my_path, nil)
    #   ETSWrapper.store_as_parent_within_pipeline(my_path, [pipeline_name])
    #   set_launch_span_attributes(metadata)
    #
    #   start_init_to_playing_span(metadata)
    # end
  end

  defp do_start_span(%{component_type: :element} = metadata) do
    # with {:ok, parent_span} <-
    #        get_parent_component_path() |> ETSWrapper.get_span() do
    # span_id = get_launch_span_id(metadata)
    # Process.put(@pdict_launch_span_id_key, span_id)

    # Membrane.OpenTelemetry.start_span(span_id, parent_span: parent_span)
    # start_span_log(span_id)
    # set_launch_span_attributes(metadata)

    # start_init_to_playing_span(metadata)
    # end
  end

  defp do_start_span(other) do
    IO.inspect(other, label: :other_metadata)
    raise "Unmatched span component type"
  end

  @spec ensure_span_ended(:telemetry.event_name(), map(), map(), any()) :: :ok
  def ensure_span_ended(
        [:membrane, :handle_start_of_stream, :stop],
        _mesaurements,
        _metadata,
        _config
      ) do
    do_ensure_launch_span_ended()
    :ok
  end

  @spec maybe_end_span(:telemetry.event_name(), map(), map(), any()) :: :ok
  def maybe_end_span([:membrane, :handle_playing, :stop], _mesaurements, metadata, _config) do
    end_init_to_playing_span(metadata)

    if get_type(metadata) in [:source, :bin, :pipeline] or only_output_pads?(metadata) do
      do_ensure_launch_span_ended()
    end

    :ok
  end

  defp only_output_pads?(metadata) do
    metadata.callback_context.pads
    |> Enum.all?(fn {_pad, data} -> data.direction == :output end)
  end

  defp do_ensure_launch_span_ended() do
    with span_id when span_id != nil <- Process.delete(@pdict_launch_span_id_key) do
      # Membrane.OpenTelemetry.end_span(span_id)
      end_span_log(span_id)
    end
  end

  @spec callback_start(:telemetry.event_name(), map(), map(), any()) :: :ok
  def callback_start([:membrane, callback, :start] = name, _measurements, metadata, _config) do
    with span_id when span_id != nil <- Process.get(@pdict_launch_span_id_key) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      event_attributes = get_callback_attributes(callback, metadata.callback_args)
      # Membrane.OpenTelemetry.add_event(span_id, event_name, event_attributes)
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
    with span_id when span_id != nil <- Process.get(@pdict_launch_span_id_key) do
      event_name = name |> Enum.map_join("_", &Atom.to_string/1)
      # Membrane.OpenTelemetry.add_event(span_id, event_name, duration: duration)
    end

    :ok
  end

  @spec pipeline_monitor(pid(), ComponentPath.t()) :: :ok
  def pipeline_monitor(pipeline_pid, pipeline_path) do
    ref = Process.monitor(pipeline_pid)

    receive do
      {:DOWN, ^ref, _process, _pid, _reason} ->
        :ok = cleanup_pipeline(pipeline_path)
    end

    :ok
  end

  defp cleanup_pipeline(pipeline_path) do
    ETSWrapper.get_parents_within_pipeline(pipeline_path)
    |> Enum.each(fn parent_path ->
      {:ok, span} = ETSWrapper.get_span(parent_path)
      ETSWrapper.delete_span_and_pipeline(parent_path, span)
      ETSWrapper.delete_parent_within_pipeline(pipeline_path, parent_path)
    end)

    :ok
  end

  @spec set_launch_span_attributes(Membrane.Telemetry.callback_span_metadata()) :: :ok
  defp set_launch_span_attributes(metadata) do
    with span_id when span_id != nil <- Process.get(@pdict_launch_span_id_key) do
      type = metadata |> get_type() |> inspect()
      # Membrane.OpenTelemetry.set_attribute(span_id, :component_type, type)

      name = get_pretty_name(metadata)
      # Membrane.OpenTelemetry.set_attribute(span_id, :component_name, name)

      module = metadata.callback_context.module |> inspect()
      # Membrane.OpenTelemetry.set_attribute(span_id, :component_module, module)
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

  defp start_init_to_playing_span(metadata) do
    launch_span =
      get_launch_span_id(metadata)

    # |> Membrane.OpenTelemetry.get_span()

    get_init_to_playing_span_id(metadata)
    # |> Membrane.OpenTelemetry.start_span(parent_span: launch_span)

    get_init_to_playing_span_id(metadata)
    |> start_span_log()

    :ok
  end

  defp end_init_to_playing_span(metadata) do
    get_init_to_playing_span_id(metadata)
    # |> Membrane.OpenTelemetry.end_span()

    get_init_to_playing_span_id(metadata)
    |> end_span_log()
  end

  defp get_launch_span_id(metadata), do: get_span_id("launch", metadata)

  defp get_init_to_playing_span_id(metadata), do: get_span_id("init_to_playing", metadata)

  defp get_span_id(span_type, metadata) do
    pretty_name_or_module =
      if metadata.component_type == :pipeline,
        do: inspect(metadata.callback_context.module),
        else: get_pretty_name(metadata)

    ["membrane", get_type(metadata), span_type, pretty_name_or_module]
    |> Enum.join("_")
  end

  defp get_pretty_name(metadata) do
    type = get_type(metadata)

    case metadata.callback_context do
      %{name: name} when is_binary(name) -> name
      %{name: name} when name != nil -> inspect(name)
      %{} -> "#{Atom.to_string(type) |> String.capitalize()} #{self() |> inspect()}"
    end
  end

  defp get_type(%{component_type: component_type} = metadata) do
    case component_type do
      :element -> metadata.callback_context.module.membrane_element_type()
      :bin -> :bin
      :pipeline -> :pipeline
    end
  end

  def get_parent_component_path() do
    my_path = ComponentPath.get()
    {_my_name, parent_path} = List.pop_at(my_path, length(my_path) - 1)
    parent_path
  end

  defp start_span_log(span_id) do
    span_log(span_id, "STARTING SPAN")
  end

  defp end_span_log(span_id) do
    span_log(span_id, "ENDING SPAN")
  end

  defp span_log(span_id, log) do
    require Logger

    Logger.warning("""
    #{log}
    SPAN_ID: #{span_id}
    COMPONENT_PATH: #{ComponentPath.get() |> inspect()}
    """)
  end
end
