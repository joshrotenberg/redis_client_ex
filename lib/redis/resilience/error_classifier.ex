if Code.ensure_loaded?(ExResilience.ErrorClassifier) do
  defmodule Redis.Resilience.ErrorClassifier do
    @moduledoc """
    Redis-specific error classifier for ExResilience.

    Classifies Redis results so that resilience patterns know which errors
    are transient (retriable / circuit-trippable) and which are permanent.

    - `Redis.ConnectionError` -- `:retriable` (transient, worth retrying)
    - `Redis.Error` -- `:ignore` (Redis app error like WRONGTYPE, not a fault)
    - Everything else -- `:ok`
    """

    @behaviour ExResilience.ErrorClassifier

    @impl true
    def classify({:error, %Redis.ConnectionError{}}), do: :retriable
    def classify({:error, %Redis.Error{}}), do: :ignore
    def classify({:error, :circuit_open}), do: :failure
    def classify({:error, :bulkhead_full}), do: :failure
    def classify({:ok, _}), do: :ok
    def classify(_), do: :ok
  end
end
