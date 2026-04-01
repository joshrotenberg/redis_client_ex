defmodule Redis.Commands.Script do
  @moduledoc """
  Command builders for Redis scripting and function operations.
  """

  @spec eval(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def eval(script, keys \\ [], args \\ []) do
    ["EVAL", script, to_string(length(keys))] ++ keys ++ args
  end

  @spec evalsha(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def evalsha(sha1, keys \\ [], args \\ []) do
    ["EVALSHA", sha1, to_string(length(keys))] ++ keys ++ args
  end

  @spec eval_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def eval_ro(script, keys \\ [], args \\ []) do
    ["EVAL_RO", script, to_string(length(keys))] ++ keys ++ args
  end

  @spec evalsha_ro(String.t(), [String.t()], [String.t()]) :: [String.t()]
  def evalsha_ro(sha1, keys \\ [], args \\ []) do
    ["EVALSHA_RO", sha1, to_string(length(keys))] ++ keys ++ args
  end

  @spec script_exists([String.t()]) :: [String.t()]
  def script_exists(sha1s) when is_list(sha1s), do: ["SCRIPT", "EXISTS" | sha1s]

  @spec script_flush(keyword()) :: [String.t()]
  def script_flush(opts \\ []) do
    if opts[:async], do: ["SCRIPT", "FLUSH", "ASYNC"], else: ["SCRIPT", "FLUSH"]
  end

  @spec script_kill() :: [String.t()]
  def script_kill, do: ["SCRIPT", "KILL"]

  @spec script_load(String.t()) :: [String.t()]
  def script_load(script), do: ["SCRIPT", "LOAD", script]

  @spec function_load(String.t(), keyword()) :: [String.t()]
  def function_load(function_code, opts \\ []) do
    cmd = ["FUNCTION", "LOAD"]
    cmd = if opts[:replace], do: cmd ++ ["REPLACE"], else: cmd
    cmd ++ [function_code]
  end

  @spec function_delete(String.t()) :: [String.t()]
  def function_delete(library_name), do: ["FUNCTION", "DELETE", library_name]

  @spec function_list(keyword()) :: [String.t()]
  def function_list(opts \\ []) do
    cmd = ["FUNCTION", "LIST"]
    cmd = if opts[:libraryname], do: cmd ++ ["LIBRARYNAME", opts[:libraryname]], else: cmd
    cmd = if opts[:withcode], do: cmd ++ ["WITHCODE"], else: cmd
    cmd
  end

  @spec function_dump() :: [String.t()]
  def function_dump, do: ["FUNCTION", "DUMP"]

  @spec function_restore(String.t(), keyword()) :: [String.t()]
  def function_restore(serialized_value, opts \\ []) do
    cmd = ["FUNCTION", "RESTORE", serialized_value]
    cond do
      opts[:flush] -> cmd ++ ["FLUSH"]
      opts[:append] -> cmd ++ ["APPEND"]
      opts[:replace] -> cmd ++ ["REPLACE"]
      true -> cmd
    end
  end

  @spec function_stats() :: [String.t()]
  def function_stats, do: ["FUNCTION", "STATS"]
end
