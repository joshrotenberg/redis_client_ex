defmodule Redis.Response.Client do
  @moduledoc """
  A parsed record returned by `CLIENT LIST` or `CLIENT INFO`.

  Fields mirror Redis' wire names where possible. `attributes` always contains
  the complete raw key/value map so new server fields remain available before
  this struct is updated.
  """

  @enforce_keys [:attributes]
  defstruct [
    :id,
    :addr,
    :laddr,
    :fd,
    :name,
    :age,
    :idle,
    :db,
    :sub,
    :psub,
    :ssub,
    :multi,
    :qbuf,
    :qbuf_free,
    :argv_mem,
    :multi_mem,
    :obl,
    :oll,
    :omem,
    :tot_mem,
    :events,
    :cmd,
    :user,
    :redir,
    :resp,
    :lib_name,
    :lib_ver,
    :io_thread,
    flags: MapSet.new(),
    attributes: %{}
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          addr: String.t() | nil,
          laddr: String.t() | nil,
          fd: integer() | nil,
          name: String.t() | nil,
          age: integer() | nil,
          idle: integer() | nil,
          flags: MapSet.t(String.t()),
          db: integer() | nil,
          sub: integer() | nil,
          psub: integer() | nil,
          ssub: integer() | nil,
          multi: integer() | nil,
          qbuf: integer() | nil,
          qbuf_free: integer() | nil,
          argv_mem: integer() | nil,
          multi_mem: integer() | nil,
          obl: integer() | nil,
          oll: integer() | nil,
          omem: integer() | nil,
          tot_mem: integer() | nil,
          events: String.t() | nil,
          cmd: String.t() | nil,
          user: String.t() | nil,
          redir: integer() | nil,
          resp: integer() | nil,
          lib_name: String.t() | nil,
          lib_ver: String.t() | nil,
          io_thread: integer() | nil,
          attributes: %{optional(String.t()) => String.t()}
        }
end

defmodule Redis.Response.StreamEntry do
  @moduledoc """
  A Redis stream entry with its ID and field/value map.
  """

  @enforce_keys [:id, :fields]
  defstruct [:id, :fields]

  @type t :: %__MODULE__{
          id: String.t(),
          fields: %{optional(String.t()) => term()} | nil
        }
end

defmodule Redis.Response.Stream do
  @moduledoc """
  A named stream and the entries returned by `XREAD` or `XREADGROUP`.
  """

  @enforce_keys [:name, :entries]
  defstruct [:name, :entries]

  @type t :: %__MODULE__{
          name: String.t(),
          entries: [Redis.Response.StreamEntry.t()]
        }
end

defmodule Redis.Response do
  @moduledoc """
  Opt-in conversion of raw Redis replies into stable Elixir values.

  Commands return raw RESP values by default. Pass `response: :typed` to
  `Redis.command/3`, `Redis.pipeline/3`, or `Redis.transaction/3` to parse
  replies whose shape is known:

    * `HGETALL` and `CONFIG GET` return maps.
    * `SMEMBERS`, `SDIFF`, `SINTER`, and `SUNION` return `MapSet`s.
    * `INFO` returns a flat key/value map. Values remain strings.
    * `CLIENT LIST` returns a list of `Redis.Response.Client` structs.
    * `CLIENT INFO` returns one `Redis.Response.Client`.
    * `XRANGE` and `XREVRANGE` return `Redis.Response.StreamEntry` structs.
    * `XREAD` and `XREADGROUP` return `Redis.Response.Stream` structs.

  Unsupported commands are returned unchanged. This makes typed mode safe for
  mixed pipelines and preserves access to module-specific replies.
  """

  alias Redis.Response.{Client, Stream, StreamEntry}

  @map_commands ~w(HGETALL)
  @set_commands ~w(SMEMBERS SDIFF SINTER SUNION)
  @range_commands ~w(XRANGE XREVRANGE)
  @read_commands ~w(XREAD XREADGROUP)

  @integer_client_fields %{
    "id" => :id,
    "fd" => :fd,
    "age" => :age,
    "idle" => :idle,
    "db" => :db,
    "sub" => :sub,
    "psub" => :psub,
    "ssub" => :ssub,
    "multi" => :multi,
    "qbuf" => :qbuf,
    "qbuf-free" => :qbuf_free,
    "argv-mem" => :argv_mem,
    "multi-mem" => :multi_mem,
    "obl" => :obl,
    "oll" => :oll,
    "omem" => :omem,
    "tot-mem" => :tot_mem,
    "redir" => :redir,
    "resp" => :resp,
    "io-thread" => :io_thread
  }

  @string_client_fields %{
    "addr" => :addr,
    "laddr" => :laddr,
    "name" => :name,
    "events" => :events,
    "cmd" => :cmd,
    "user" => :user,
    "lib-name" => :lib_name,
    "lib-ver" => :lib_ver
  }

  @typed_mode :typed
  @raw_mode :raw

  @doc false
  @spec decode({:ok, term()} | {:error, term()}, [term()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def decode(result, command, opts) do
    case Keyword.get(opts, :response, @raw_mode) do
      @raw_mode ->
        result

      @typed_mode ->
        decode_typed(result, command)

      mode ->
        response_error(command, nil, {:invalid_response_mode, mode})
    end
  end

  @doc false
  @spec decode_many({:ok, [term()]} | {:error, term()}, [[term()]], keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def decode_many(result, commands, opts) do
    case Keyword.get(opts, :response, @raw_mode) do
      @raw_mode ->
        result

      @typed_mode ->
        decode_many_typed(result, commands)

      mode ->
        response_error(nil, nil, {:invalid_response_mode, mode})
    end
  end

  @doc """
  Parses one raw reply using its command.

  Unknown commands return `{:ok, response}` unchanged. A malformed reply for a
  supported command returns `{:error, %Redis.ResponseError{}}`.
  """
  @spec parse([term()], term()) :: {:ok, term()} | {:error, Redis.ResponseError.t()}
  def parse(command, response) when is_list(command) do
    case do_parse(command, response) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> response_error(command, response, reason)
    end
  end

  defp decode_typed({:ok, response}, command), do: parse(command, response)
  defp decode_typed({:error, _reason} = error, _command), do: error

  defp decode_many_typed({:error, _reason} = error, _commands), do: error

  defp decode_many_typed({:ok, responses}, commands)
       when is_list(responses) and length(responses) == length(commands) do
    commands
    |> Enum.zip(responses)
    |> Enum.reduce_while({:ok, []}, fn
      {_command, %Redis.Error{} = error}, {:ok, parsed} ->
        {:cont, {:ok, [error | parsed]}}

      {command, response}, {:ok, parsed} ->
        case parse(command, response) do
          {:ok, value} -> {:cont, {:ok, [value | parsed]}}
          {:error, _reason} = error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp decode_many_typed({:ok, responses}, commands) do
    response_error(commands, responses, :response_count_mismatch)
  end

  defp do_parse([command | rest] = full_command, response) when is_binary(command) do
    command
    |> String.upcase()
    |> parse_command(rest, full_command, response)
  end

  defp do_parse(_command, response), do: {:ok, response}

  defp parse_command(command, _rest, _full_command, response) when command in @map_commands,
    do: parse_map(response)

  defp parse_command("CONFIG", rest, _full_command, response) do
    if subcommand(rest) == "GET", do: parse_map(response), else: {:ok, response}
  end

  defp parse_command(command, _rest, _full_command, response) when command in @set_commands,
    do: parse_set(response)

  defp parse_command("INFO", _rest, _full_command, response), do: parse_info(response)

  defp parse_command("CLIENT", rest, _full_command, response) do
    case subcommand(rest) do
      "LIST" -> parse_client_list(response)
      "INFO" -> parse_client_info(response)
      _other -> {:ok, response}
    end
  end

  defp parse_command(command, _rest, _full_command, response) when command in @range_commands,
    do: parse_entries(response)

  defp parse_command(command, _rest, full_command, response) when command in @read_commands,
    do: parse_streams(full_command, response)

  defp parse_command(_command, _rest, _full_command, response), do: {:ok, response}

  defp subcommand([subcommand | _]) when is_binary(subcommand), do: String.upcase(subcommand)
  defp subcommand(_), do: nil

  defp parse_map(response) when is_map(response), do: {:ok, response}

  defp parse_map(response) when is_list(response) do
    if rem(length(response), 2) == 0 do
      {:ok, response |> Enum.chunk_every(2) |> Map.new(fn [key, value] -> {key, value} end)}
    else
      {:error, :odd_map_response}
    end
  end

  defp parse_map(_response), do: {:error, :expected_map_or_flat_list}

  defp parse_set(%MapSet{} = response), do: {:ok, response}
  defp parse_set(response) when is_list(response), do: {:ok, MapSet.new(response)}
  defp parse_set(_response), do: {:error, :expected_set_or_list}

  defp parse_info(response) when is_binary(response) do
    info =
      response
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.reduce(%{}, fn line, info ->
        case String.split(line, ":", parts: 2) do
          [key, value] -> Map.put(info, key, value)
          _malformed -> info
        end
      end)

    {:ok, info}
  end

  defp parse_info(_response), do: {:error, :expected_info_string}

  defp parse_client_list(response) when is_binary(response) do
    response
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, clients} ->
      case parse_client(line) do
        {:ok, client} -> {:cont, {:ok, [client | clients]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clients} -> {:ok, Enum.reverse(clients)}
      error -> error
    end
  end

  defp parse_client_list(_response), do: {:error, :expected_client_list_string}

  defp parse_client_info(response) when is_binary(response),
    do: parse_client(String.trim(response))

  defp parse_client_info(_response), do: {:error, :expected_client_info_string}

  defp parse_client(""), do: {:error, :empty_client_record}

  defp parse_client(line) do
    attributes =
      line
      |> String.split(" ", trim: true)
      |> Enum.reduce(%{}, fn token, attributes ->
        case String.split(token, "=", parts: 2) do
          [key, value] -> Map.put(attributes, key, value)
          _malformed -> attributes
        end
      end)

    client =
      Enum.reduce(@string_client_fields, %Client{attributes: attributes}, fn
        {wire_name, field}, client -> Map.put(client, field, attributes[wire_name])
      end)

    with {:ok, client} <- put_integer_client_fields(client, attributes) do
      {:ok, %{client | flags: parse_flags(attributes["flags"])}}
    end
  end

  defp put_integer_client_fields(client, attributes) do
    Enum.reduce_while(@integer_client_fields, {:ok, client}, fn
      {wire_name, field}, {:ok, client} ->
        case parse_optional_integer(attributes[wire_name]) do
          {:ok, value} -> {:cont, {:ok, Map.put(client, field, value)}}
          :error -> {:halt, {:error, {:invalid_client_integer, wire_name}}}
        end
    end)
  end

  defp parse_optional_integer(nil), do: {:ok, nil}

  defp parse_optional_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> :error
    end
  end

  defp parse_flags(nil), do: MapSet.new()
  defp parse_flags(flags), do: flags |> String.graphemes() |> MapSet.new()

  defp parse_entries(response) when is_list(response) do
    response
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, entries} ->
      case parse_entry(entry) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | entries]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp parse_entries(_response), do: {:error, :expected_stream_entries}

  defp parse_entry([id, nil]) when is_binary(id),
    do: {:ok, %StreamEntry{id: id, fields: nil}}

  defp parse_entry([id, fields]) when is_binary(id) do
    case parse_map(fields) do
      {:ok, fields} -> {:ok, %StreamEntry{id: id, fields: fields}}
      {:error, reason} -> {:error, {:invalid_stream_fields, reason}}
    end
  end

  defp parse_entry(_entry), do: {:error, :invalid_stream_entry}

  defp parse_streams(_command, nil), do: {:ok, nil}

  defp parse_streams(command, response) when is_map(response) do
    requested_names = stream_names(command)
    response_names = Map.keys(response)

    names =
      requested_names ++
        (response_names
         |> Enum.reject(&(&1 in requested_names))
         |> Enum.sort())

    names
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, streams} ->
      case Map.fetch(response, name) do
        {:ok, entries} -> add_stream(name, entries, streams)
        :error -> {:cont, {:ok, streams}}
      end
    end)
    |> reverse_streams()
  end

  defp parse_streams(_command, response) when is_list(response) do
    response
    |> Enum.reduce_while({:ok, []}, fn
      [name, entries], {:ok, streams} when is_binary(name) ->
        case parse_entries(entries) do
          {:ok, entries} ->
            {:cont, {:ok, [%Stream{name: name, entries: entries} | streams]}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_stream_response}}
    end)
    |> reverse_streams()
  end

  defp parse_streams(_command, _response), do: {:error, :expected_stream_response}

  defp reverse_streams({:ok, streams}), do: {:ok, Enum.reverse(streams)}
  defp reverse_streams(error), do: error

  defp add_stream(name, entries, streams) do
    case parse_entries(entries) do
      {:ok, entries} ->
        {:cont, {:ok, [%Stream{name: name, entries: entries} | streams]}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp stream_names(command) do
    case Enum.find_index(command, &(is_binary(&1) and String.upcase(&1) == "STREAMS")) do
      nil ->
        []

      streams_index ->
        stream_args = Enum.drop(command, streams_index + 1)
        Enum.take(stream_args, div(length(stream_args), 2))
    end
  end

  defp response_error(command, response, reason) do
    {:error, %Redis.ResponseError{command: command, response: response, reason: reason}}
  end
end
