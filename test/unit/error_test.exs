defmodule Redis.ErrorTest do
  use ExUnit.Case, async: true

  describe "Redis.Error" do
    test "is an exception" do
      assert Exception.exception?(Redis.Error.exception(message: "ERR test"))
    end

    test "has message field" do
      err = %Redis.Error{message: "ERR unknown command"}
      assert err.message == "ERR unknown command"
    end

    test "formats as string" do
      err = %Redis.Error{message: "ERR test error"}
      assert Exception.message(err) =~ "ERR test error"
    end

    test "pattern matches in case" do
      err = %Redis.Error{message: "WRONGTYPE Operation"}

      result =
        case err do
          %Redis.Error{message: "WRONGTYPE" <> _} -> :wrong_type
          %Redis.Error{} -> :other
        end

      assert result == :wrong_type
    end
  end

  describe "Redis.ConnectionError" do
    test "is an exception" do
      assert Exception.exception?(Redis.ConnectionError.exception(reason: :econnrefused))
    end

    test "has reason field" do
      err = %Redis.ConnectionError{reason: :timeout}
      assert err.reason == :timeout
    end

    test "formats as string" do
      err = %Redis.ConnectionError{reason: :econnrefused}
      assert Exception.message(err) =~ "econnrefused"
    end
  end
end
