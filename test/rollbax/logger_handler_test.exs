defmodule Rollbax.LoggerHandlerTest do
  use ExUnit.Case

  defmodule TestReporter do
    @behaviour Rollbax.Reporter

    def handle_event(level, {Logger, message, time, metadata}) do
      send(self(), {:reporter_called, level, message, time, metadata})
      :ignore
    end
  end

  describe "string messages" do
    test "handles regular string messages" do
      event = %{
        level: :debug,
        meta: %{time: 555_555_555, pid: self()},
        msg: {:string, "This is a regular log message"}
      }

      config = %{config: %{reporters: [TestReporter]}}

      Rollbax.LoggerHandler.log(event, config)

      assert_receive {:reporter_called, :debug, message, 555_555_555, _metadata}
      assert message == "This is a regular log message"
    end
  end

  describe "format string messages" do
    test "handles charlist format with arguments" do
      event = %{
        level: :info,
        meta: %{
          file: ~c"/app/deps/opentelemetry/src/otel_span_sweeper.erl",
          gl: self(),
          line: 118,
          mfa: {:otel_span_sweeper, :sweep_spans, 2},
          pid: self(),
          time: 1_748_712_646_180_971
        },
        msg: {~c"sweep old spans: ttl=~p num_dropped=~p", [1_800_000_000_000, 8]}
      }

      config = %{config: %{reporters: [TestReporter]}}

      Rollbax.LoggerHandler.log(event, config)

      assert_receive {:reporter_called, :info, message, time, metadata}

      assert message == "sweep old spans: ttl=1800000000000 num_dropped=8"
      assert time == 1_748_712_646_180_971
      assert metadata[:mfa] == {:otel_span_sweeper, :sweep_spans, 2}
      assert metadata[:line] == 118
    end

    test "handles simple format strings" do
      event = %{
        level: :warning,
        meta: %{time: 123_456_789, pid: self()},
        msg: {~c"Connection failed: ~s", ["timeout"]}
      }

      config = %{config: %{reporters: [TestReporter]}}

      Rollbax.LoggerHandler.log(event, config)

      assert_receive {:reporter_called, :warning, message, 123_456_789, _metadata}
      assert message == "Connection failed: timeout"
    end

    test "handles numeric format placeholders" do
      event = %{
        level: :error,
        meta: %{time: 987_654_321, pid: self()},
        msg: {~c"Error code ~w with retry count ~p", [404, 3]}
      }

      config = %{config: %{reporters: [TestReporter]}}

      Rollbax.LoggerHandler.log(event, config)

      assert_receive {:reporter_called, :error, message, 987_654_321, _metadata}
      assert message == "Error code 404 with retry count 3"
    end
  end

  describe "unhandled message formats" do
    test "skips events with unknown message format" do
      event = %{
        level: :info,
        meta: %{time: 111_111_111, pid: self()},
        msg: {:unknown_format, "some data"}
      }

      config = %{config: %{reporters: [TestReporter]}}

      # This should not crash and should not call the reporter
      Rollbax.LoggerHandler.log(event, config)

      refute_receive {:reporter_called, _, _, _, _}, 100
    end
  end
end
