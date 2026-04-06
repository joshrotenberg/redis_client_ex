defmodule Redis.Hook do
  @moduledoc """
  Behaviour for Redis command hooks (middleware).

  Hooks allow you to intercept commands before they are sent to Redis and
  inspect or transform results after they return. Common uses include logging,
  metrics, command rewriting, and access control.

  ## Defining a hook

  Implement the callbacks you need and `use Redis.Hook` to get defaults for
  the rest:

      defmodule MyApp.LoggingHook do
        use Redis.Hook

        @impl Redis.Hook
        def before_command(command, _context) do
          Logger.info("redis command: \#{inspect(command)}")
          {:ok, command}
        end
      end

  ## Using hooks

  Pass hooks when starting a connection:

      Redis.Connection.start_link(
        port: 6379,
        hooks: [MyApp.LoggingHook, MyApp.MetricsHook]
      )

  `before_*` hooks run in the order given. `after_*` hooks run in reverse
  order (outermost hook sees the final result last, like middleware).

  If any `before_*` hook returns `{:error, reason}`, the command is
  short-circuited and the error is returned to the caller without reaching
  Redis.
  """

  @type command :: [String.t()]
  @type result :: {:ok, term()} | {:error, term()}
  @type context :: %{host: String.t(), port: integer(), database: non_neg_integer()}

  @doc "Called before a single command is sent. Return `{:ok, command}` to proceed or `{:error, reason}` to short-circuit."
  @callback before_command(command(), context()) :: {:ok, command()} | {:error, term()}

  @doc "Called after a single command completes. May transform the result."
  @callback after_command(command(), result(), context()) :: result()

  @doc "Called before a pipeline is sent. Return `{:ok, commands}` to proceed or `{:error, reason}` to short-circuit."
  @callback before_pipeline([command()], context()) :: {:ok, [command()]} | {:error, term()}

  @doc "Called after a pipeline completes. May transform the result."
  @callback after_pipeline([command()], result(), context()) :: result()

  @optional_callbacks before_command: 2, after_command: 3, before_pipeline: 2, after_pipeline: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour Redis.Hook

      @impl Redis.Hook
      def before_command(command, _context), do: {:ok, command}

      @impl Redis.Hook
      def after_command(_command, result, _context), do: result

      @impl Redis.Hook
      def before_pipeline(commands, _context), do: {:ok, commands}

      @impl Redis.Hook
      def after_pipeline(_commands, result, _context), do: result

      defoverridable before_command: 2, after_command: 3, before_pipeline: 2, after_pipeline: 3
    end
  end

  # ------------------------------------------------------------------
  # Hook chain execution
  # ------------------------------------------------------------------

  @doc false
  @spec run_before_command([module()], command(), context()) ::
          {:ok, command()} | {:error, term()}
  def run_before_command([], command, _context), do: {:ok, command}

  def run_before_command([hook | rest], command, context) do
    case hook.before_command(command, context) do
      {:ok, command} -> run_before_command(rest, command, context)
      {:error, _} = err -> err
    end
  end

  @doc false
  @spec run_after_command([module()], command(), result(), context()) :: result()
  def run_after_command(hooks, command, result, context) do
    Enum.reduce(Enum.reverse(hooks), result, fn hook, acc ->
      hook.after_command(command, acc, context)
    end)
  end

  @doc false
  @spec run_before_pipeline([module()], [command()], context()) ::
          {:ok, [command()]} | {:error, term()}
  def run_before_pipeline([], commands, _context), do: {:ok, commands}

  def run_before_pipeline([hook | rest], commands, context) do
    case hook.before_pipeline(commands, context) do
      {:ok, commands} -> run_before_pipeline(rest, commands, context)
      {:error, _} = err -> err
    end
  end

  @doc false
  @spec run_after_pipeline([module()], [command()], result(), context()) :: result()
  def run_after_pipeline(hooks, commands, result, context) do
    Enum.reduce(Enum.reverse(hooks), result, fn hook, acc ->
      hook.after_pipeline(commands, acc, context)
    end)
  end

  @doc false
  @spec build_context(map()) :: context()
  def build_context(state) do
    %{
      host: Map.get(state, :host, "127.0.0.1"),
      port: Map.get(state, :port, 6379),
      database: Map.get(state, :database) || 0
    }
  end
end
