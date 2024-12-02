defmodule Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper do
  @pid_to_span_and_pipeline_ets :__membrane_opentelemetry_plugs_launch_pid_to_span_and_pipeline__
  @pipeline_pid_to_parents_ets :__membrane_opentelemetry_plugs_launch_pipeline_pid_to_parents__

  @spec setup_ets_tables() :: :ok
  def setup_ets_tables() do
    :ets.new(@pid_to_span_and_pipeline_ets, [
      :public,
      # unique keys
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    :ets.new(@pipeline_pid_to_parents_ets, [
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
    :ets.delete(@pid_to_span_and_pipeline_ets)
    :ets.delete(@pipeline_pid_to_parents_ets)
    :ok
  end

  @spec get_span_and_pipeline(pid()) :: {:ok, OpenTelemetry.span_ctx(), pid()} | :error
  def get_span_and_pipeline(pid) do
    case :ets.lookup(@pid_to_span_and_pipeline_ets, pid) do
      [{^pid, {span_ctx, pipeline}}] -> {:ok, span_ctx, pipeline}
      [] -> :error
    end
  end

  @spec store_span_and_pipeline(OpenTelemetry.span_ctx(), pid()) :: :ok
  def store_span_and_pipeline(span_ctx, pipeline) do
    :ets.insert(@pid_to_span_and_pipeline_ets, {self(), {span_ctx, pipeline}})
    :ok
  end

  def delete_span_and_pipeline(component_pid, span_ctx, pipeline) do
    :ets.delete(@pid_to_span_and_pipeline_ets, {component_pid, {span_ctx, pipeline}})
  end

  def store_as_parent_within_pipeline(pipeline) do
    :ets.insert(@pipeline_pid_to_parents_ets, {pipeline, self()})
    :ok
  end

  def get_parents_within_pipeline(pipeline) do
    :ets.lookup(@pipeline_pid_to_parents_ets, pipeline)
    |> Enum.map(fn {^pipeline, component} -> component end)
  end

  def delete_parent_within_pipeline(pipeline, parent) do
    :ets.delete(@pipeline_pid_to_parents_ets, {pipeline, parent})
  end
end
