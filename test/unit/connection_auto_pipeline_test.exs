defmodule Redis.Connection.AutoPipelineOptionsTest do
  use ExUnit.Case, async: true

  alias Redis.Connection

  test "rejects a non-boolean auto_pipeline option" do
    assert {:error, {:invalid_auto_pipeline, :yes}} =
             Connection.start_link(auto_pipeline: :yes)
  end

  test "rejects a negative or non-integer batch window" do
    assert {:error, {:invalid_auto_pipeline_window, -1}} =
             Connection.start_link(auto_pipeline_window: -1)

    assert {:error, {:invalid_auto_pipeline_window, 1.5}} =
             Connection.start_link(auto_pipeline_window: 1.5)
  end

  test "rejects a non-positive maximum batch size" do
    assert {:error, {:invalid_auto_pipeline_max_size, 0}} =
             Connection.start_link(auto_pipeline_max_size: 0)

    assert {:error, {:invalid_auto_pipeline_max_size, -10}} =
             Connection.start_link(auto_pipeline_max_size: -10)
  end
end
