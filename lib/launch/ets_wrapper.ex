defmodule Membrane.OpenTelemetry.Plugs.Launch.ETSWrapper do
  alias Membrane.ComponentPath

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

  @spec get_span(ComponentPath.t()) :: {:ok, OpenTelemetry.span_ctx()} | :error
  def get_span(component_path) do
    case :ets.lookup(@component_path_to_span_ets, component_path) do
      [{^component_path, span}] -> {:ok, span}
      [] -> {:ok, nil}
    end
  end

  @spec store_span(ComponentPath.t(), OpenTelemetry.span_ctx()) :: :ok
  def store_span(component_path, span) do
    :ets.insert(@component_path_to_span_ets, {component_path, span})
    :ok
  end

  @spec delete_span_and_pipeline(ComponentPath.t(), OpenTelemetry.span_ctx()) :: :ok
  def delete_span_and_pipeline(component_path, span) do
    :ets.delete(@component_path_to_span_ets, {component_path, span})
    :ok
  end

  @spec store_as_parent_within_pipeline(ComponentPath.t(), ComponentPath.t()) :: :ok
  def store_as_parent_within_pipeline(my_component_path, pipeline_path) do
    :ets.insert(@pipeline_to_parents_ets, {pipeline_path, my_component_path})
    :ok
  end

  @spec get_parents_within_pipeline(ComponentPath.t()) :: [ComponentPath.t()]
  def get_parents_within_pipeline(pipeline_path) do
    :ets.lookup(@pipeline_to_parents_ets, pipeline_path)
    |> Enum.map(fn {^pipeline_path, component_path} -> component_path end)
  end

  @spec delete_parent_within_pipeline(ComponentPath.t(), ComponentPath.t()) :: :ok
  def delete_parent_within_pipeline(pipeline_path, parent_path) do
    :ets.delete(@pipeline_to_parents_ets, {pipeline_path, parent_path})
    :ok
  end
end
