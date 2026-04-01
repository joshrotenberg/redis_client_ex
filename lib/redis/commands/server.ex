defmodule Redis.Commands.Server do
  @moduledoc """
  Command builders for Redis server operations.

  ## TODO (Phase 2)

  CLIENT, CONFIG, DBSIZE, DEBUG, FLUSHALL, FLUSHDB, INFO,
  LASTSAVE, MONITOR, PSYNC, REPLICAOF, SAVE, SHUTDOWN, SLOWLOG,
  TIME, WAIT
  """

  @spec ping(String.t() | nil) :: [String.t()]
  def ping(message \\ nil) do
    if message, do: ["PING", message], else: ["PING"]
  end

  @spec info(String.t() | nil) :: [String.t()]
  def info(section \\ nil) do
    if section, do: ["INFO", section], else: ["INFO"]
  end

  @spec dbsize() :: [String.t()]
  def dbsize, do: ["DBSIZE"]

  @spec flushdb(keyword()) :: [String.t()]
  def flushdb(opts \\ []) do
    if opts[:async], do: ["FLUSHDB", "ASYNC"], else: ["FLUSHDB"]
  end

  @spec client_setname(String.t()) :: [String.t()]
  def client_setname(name), do: ["CLIENT", "SETNAME", name]

  @spec client_getname() :: [String.t()]
  def client_getname, do: ["CLIENT", "GETNAME"]

  @spec client_id() :: [String.t()]
  def client_id, do: ["CLIENT", "ID"]

  @spec client_info() :: [String.t()]
  def client_info, do: ["CLIENT", "INFO"]

  @spec client_list(keyword()) :: [String.t()]
  def client_list(opts \\ []) do
    cmd = ["CLIENT", "LIST"]
    cmd = if opts[:type], do: cmd ++ ["TYPE", opts[:type]], else: cmd
    cmd = if opts[:id], do: cmd ++ ["ID" | Enum.map(List.wrap(opts[:id]), &to_string/1)], else: cmd
    cmd
  end

  @spec client_kill(keyword()) :: [String.t()]
  def client_kill(opts \\ []) do
    cmd = ["CLIENT", "KILL"]
    cmd = if opts[:id], do: cmd ++ ["ID", to_string(opts[:id])], else: cmd
    cmd = if opts[:addr], do: cmd ++ ["ADDR", opts[:addr]], else: cmd
    cmd = if opts[:user], do: cmd ++ ["USER", opts[:user]], else: cmd
    cmd
  end

  @spec client_tracking(boolean(), keyword()) :: [String.t()]
  def client_tracking(on_off, opts \\ []) do
    cmd = ["CLIENT", "TRACKING", if(on_off, do: "ON", else: "OFF")]
    cmd = if opts[:redirect], do: cmd ++ ["REDIRECT", to_string(opts[:redirect])], else: cmd
    cmd = if opts[:prefix], do: cmd ++ Enum.flat_map(List.wrap(opts[:prefix]), fn p -> ["PREFIX", p] end), else: cmd
    cmd = if opts[:bcast], do: cmd ++ ["BCAST"], else: cmd
    cmd = if opts[:optin], do: cmd ++ ["OPTIN"], else: cmd
    cmd = if opts[:optout], do: cmd ++ ["OPTOUT"], else: cmd
    cmd = if opts[:noloop], do: cmd ++ ["NOLOOP"], else: cmd
    cmd
  end

  @spec config_get(String.t()) :: [String.t()]
  def config_get(parameter), do: ["CONFIG", "GET", parameter]

  @spec config_set(String.t(), String.t()) :: [String.t()]
  def config_set(parameter, value), do: ["CONFIG", "SET", parameter, value]

  @spec config_resetstat() :: [String.t()]
  def config_resetstat, do: ["CONFIG", "RESETSTAT"]

  @spec config_rewrite() :: [String.t()]
  def config_rewrite, do: ["CONFIG", "REWRITE"]

  @spec slowlog_get(integer() | nil) :: [String.t()]
  def slowlog_get(count \\ nil) do
    if count, do: ["SLOWLOG", "GET", to_string(count)], else: ["SLOWLOG", "GET"]
  end

  @spec slowlog_len() :: [String.t()]
  def slowlog_len, do: ["SLOWLOG", "LEN"]

  @spec slowlog_reset() :: [String.t()]
  def slowlog_reset, do: ["SLOWLOG", "RESET"]

  @spec time() :: [String.t()]
  def time, do: ["TIME"]

  @spec save() :: [String.t()]
  def save, do: ["SAVE"]

  @spec bgsave(keyword()) :: [String.t()]
  def bgsave(opts \\ []) do
    if opts[:schedule], do: ["BGSAVE", "SCHEDULE"], else: ["BGSAVE"]
  end

  @spec bgrewriteaof() :: [String.t()]
  def bgrewriteaof, do: ["BGREWRITEAOF"]

  @spec flushall(keyword()) :: [String.t()]
  def flushall(opts \\ []) do
    if opts[:async], do: ["FLUSHALL", "ASYNC"], else: ["FLUSHALL"]
  end

  @spec lastsave() :: [String.t()]
  def lastsave, do: ["LASTSAVE"]

  @spec role() :: [String.t()]
  def role, do: ["ROLE"]

  @spec replicaof(String.t(), integer()) :: [String.t()]
  def replicaof(host, port), do: ["REPLICAOF", host, to_string(port)]

  @spec acl_list() :: [String.t()]
  def acl_list, do: ["ACL", "LIST"]

  @spec acl_getuser(String.t()) :: [String.t()]
  def acl_getuser(username), do: ["ACL", "GETUSER", username]

  @spec acl_setuser(String.t(), [String.t()]) :: [String.t()]
  def acl_setuser(username, rules \\ []), do: ["ACL", "SETUSER", username | rules]

  @spec acl_deluser([String.t()]) :: [String.t()]
  def acl_deluser(usernames) when is_list(usernames), do: ["ACL", "DELUSER" | usernames]

  @spec acl_cat(String.t() | nil) :: [String.t()]
  def acl_cat(category \\ nil) do
    if category, do: ["ACL", "CAT", category], else: ["ACL", "CAT"]
  end

  @spec acl_log(keyword()) :: [String.t()]
  def acl_log(opts \\ []) do
    cmd = ["ACL", "LOG"]
    cond do
      opts[:reset] -> cmd ++ ["RESET"]
      opts[:count] -> cmd ++ [to_string(opts[:count])]
      true -> cmd
    end
  end

  @spec command_count() :: [String.t()]
  def command_count, do: ["COMMAND", "COUNT"]

  @spec command_info([String.t()]) :: [String.t()]
  def command_info(command_names) when is_list(command_names), do: ["COMMAND", "INFO" | command_names]

  @spec command_list(keyword()) :: [String.t()]
  def command_list(opts \\ []) do
    cmd = ["COMMAND", "LIST"]
    cmd = if opts[:filterby], do: cmd ++ ["FILTERBY" | List.wrap(opts[:filterby])], else: cmd
    cmd
  end

  @spec debug_sleep(integer()) :: [String.t()]
  def debug_sleep(seconds), do: ["DEBUG", "SLEEP", to_string(seconds)]

  @spec memory_usage(String.t(), keyword()) :: [String.t()]
  def memory_usage(key, opts \\ []) do
    cmd = ["MEMORY", "USAGE", key]
    if opts[:samples], do: cmd ++ ["SAMPLES", to_string(opts[:samples])], else: cmd
  end

  @spec swapdb(integer(), integer()) :: [String.t()]
  def swapdb(index1, index2), do: ["SWAPDB", to_string(index1), to_string(index2)]

  @spec object_help() :: [String.t()]
  def object_help, do: ["OBJECT", "HELP"]

  @spec echo(String.t()) :: [String.t()]
  def echo(message), do: ["ECHO", message]

  @spec shutdown(keyword()) :: [String.t()]
  def shutdown(opts \\ []) do
    cmd = ["SHUTDOWN"]
    cmd = if opts[:nosave], do: cmd ++ ["NOSAVE"], else: cmd
    cmd = if opts[:save], do: cmd ++ ["SAVE"], else: cmd
    cmd = if opts[:now], do: cmd ++ ["NOW"], else: cmd
    cmd = if opts[:force], do: cmd ++ ["FORCE"], else: cmd
    cmd
  end

  @spec latency_latest() :: [String.t()]
  def latency_latest, do: ["LATENCY", "LATEST"]

  @spec latency_history(String.t()) :: [String.t()]
  def latency_history(event), do: ["LATENCY", "HISTORY", event]

  @spec latency_reset(keyword()) :: [String.t()]
  def latency_reset(opts \\ []) do
    cmd = ["LATENCY", "RESET"]
    if opts[:events], do: cmd ++ opts[:events], else: cmd
  end

  @spec waitaof(integer(), integer(), integer()) :: [String.t()]
  def waitaof(numlocal, numreplicas, timeout) do
    ["WAITAOF", to_string(numlocal), to_string(numreplicas), to_string(timeout)]
  end

  @doc "Deprecated: use replicaof/2 instead."
  @spec slaveof(String.t(), integer()) :: [String.t()]
  def slaveof(host, port), do: ["SLAVEOF", host, to_string(port)]
end
