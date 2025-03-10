defmodule Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper do
  alias Membrane.ComponentPath
  @pid_to_span_and_pipeline_ets :__membrane_opentelemetry_plugs_launch_pid_to_span_and_pipeline__
  @pipeline_pid_to_parents_ets :__membrane_opentelemetry_plugs_launch_pipeline_pid_to_parents__

  @component_path_to_span_ets :__membrane_opentelemetry_plugs_component_path_to_span__
  @pipeline_to_parents_ets :__membrane_opentelemetry_plugs_launch_pipeline_to_parents__

  @spec setup_ets_tables() :: :ok
  def setup_ets_tables() do
    :ets.new(@component_path_to_span_ets, [
      :public,
      # unique keys
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    :ets.new(@pipeline_to_parents_ets, [
      :public,
      # allows duplicates
      :bag,
      :named_table,
      {:read_concurrency, true}
    ])

    :ok
  end

  @spec delete_ets_tables() :: :ok
  def delete_ets_tables() do
    :ets.delete(@component_path_to_span_ets)
    :ets.delete(@pipeline_to_parents_ets)
    :ok
  end

  @spec get_span_and_pipeline(pid()) :: {:ok, OpenTelemetry.span_ctx(), pid()} | :error
  def get_span_and_pipeline(pid) do
    case :ets.lookup(@pid_to_span_and_pipeline_ets, pid) do
      [{^pid, {span_ctx, pipeline}}] -> {:ok, span_ctx, pipeline}
      [] -> :error
    end
  end

  @spec store_span(ComponentPath.t(), OpenTelemetry.span_ctx()) :: :ok
  def store_span(component_path, span_ctx) do
    :ets.insert(@pid_to_span_and_pipeline_ets, {component_path, span_ctx})
    :ok
  end

  def delete_span_and_pipeline(component_path, span_ctx) do
    :ets.delete(@pid_to_span_and_pipeline_ets, {component_path, span_ctx})
  end

  def store_as_parent_within_pipeline(my_component_path, pipeline_path) do
    :ets.insert(@pipeline_to_parents_ets, {pipeline, my_component_path})
    :ok
  end

  def get_parents_within_pipeline(pipeline_path) do
    :ets.lookup(@pipeline_pid_to_parents_ets, pipeline_path)
    |> Enum.map(fn {^pipeline_path, component_path} -> component_path end)
  end

  def delete_parent_within_pipeline(pipeline_path, parent_path) do
    :ets.delete(@pipeline_pid_to_parents_ets, {pipeline_path, parent_path})
  end
end
