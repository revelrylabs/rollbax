defmodule Rollbax.Reporter.Standard do
  @moduledoc """
  A `Rollbax.Reporter` that translates crashes and exits from processes to nicely-formatted
  Rollbar exceptions.
  """

  @behaviour Rollbax.Reporter

  def handle_event(:error, {_Logger, msg, _timestamp, meta}) do
    format_exception(msg, meta)
  end

  def handle_event(level, event) do
    IO.inspect(%{level: level, event: event}, label: "unhandled event shape")
    :next
  end

  defp format_exception(["GenServer ", pid, " terminating", details | _] = msg, meta) do
    case meta[:crash_reason] do
      {exception, stacktrace}
      when is_list(stacktrace) and is_exception(exception) ->
        %Rollbax.Exception{
          class: "GenServer terminating (#{exception_name(exception)})",
          message: Exception.message(exception),
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid
          }
        }

      {:stop_reason, []} ->
        %Rollbax.Exception{
          class: "GenServer terminating (stop)",
          message: IO.iodata_to_binary(msg),
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid
          }
        }

      _other ->
        [_prefix | message] = hd(details)

        %Rollbax.Exception{
          class: "GenServer terminating",
          message: message,
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid
          }
        }
    end
  end

  # Errors in a GenServer.
  def handle_error_format(~c"** Generic server " ++ _, [name, last_message, state, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "GenServer terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "last_message" => inspect(last_message),
        "state" => inspect(state)
      }
    }
  end

  # Errors in a GenEvent handler.
  def handle_error_format(~c"** gen_event handler " ++ _, [
        name,
        manager,
        last_message,
        state,
        reason
      ]) do
    {class, message, stacktrace} = format_as_exception(reason, "gen_event handler terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "manager" => inspect(manager),
        "last_message" => inspect(last_message),
        "state" => inspect(state)
      }
    }
  end

  # Errors in a task.
  def handle_error_format(~c"** Task " ++ _, [name, starter, function, arguments, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "Task terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "started_from" => inspect(starter),
        "function" => inspect(function),
        "arguments" => inspect(arguments)
      }
    }
  end

  def handle_error_format(~c"** State machine " ++ _ = message, data) do
    if charlist_contains?(message, ~c"Callback mode") do
      :next
    else
      handle_gen_fsm_error(data)
    end
  end

  # Errors in a regular process.
  def handle_error_format(~c"Error in process " ++ _, [pid, {reason, stacktrace}]) do
    exception = Exception.normalize(:error, reason)

    %Rollbax.Exception{
      class: "error in process (#{inspect(exception.__struct__)})",
      message: Exception.message(exception),
      stacktrace: stacktrace,
      custom: %{
        "pid" => inspect(pid)
      }
    }
  end

  # Any other error (for example, the ones logged through
  # :error_logger.error_msg/1). This reporter doesn't report those to Rollbar.
  def handle_error_format(_format, _data) do
    :next
  end

  def handle_gen_fsm_error([name, last_event, state, data, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "State machine terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "last_event" => inspect(last_event),
        "state" => inspect(state),
        "data" => inspect(data)
      }
    }
  end

  def handle_gen_fsm_error(_data) do
    :next
  end

  def format_as_exception({maybe_exception, [_ | _] = maybe_stacktrace} = reason, class) do
    # We do this &Exception.format_stacktrace_entry/1 dance just to ensure that
    # "maybe_stacktrace" is a valid stacktrace. If it's not,
    # Exception.format_stacktrace_entry/1 will raise an error and we'll treat it
    # as not a stacktrace.
    try do
      Enum.each(maybe_stacktrace, &Exception.format_stacktrace_entry/1)
    catch
      :error, _ ->
        format_stop_as_exception(reason, class)
    else
      :ok ->
        format_error_as_exception(maybe_exception, maybe_stacktrace, class)
    end
  end

  def format_as_exception(reason, class) do
    format_stop_as_exception(reason, class)
  end

  def format_stop_as_exception(reason, class) do
    {class <> " (stop)", Exception.format_exit(reason), _stacktrace = []}
  end

  def format_error_as_exception(reason, stacktrace, class) do
    case Exception.normalize(:error, reason, stacktrace) do
      %ErlangError{} ->
        {class, Exception.format_exit(reason), stacktrace}

      exception ->
        class = class <> " (" <> inspect(exception.__struct__) <> ")"
        {class, Exception.message(exception), stacktrace}
    end
  end

  def charlist_contains?(charlist, part) do
    :string.str(charlist, part) != 0
  end

  defp stacktrace({_, trace} = _crash_reason) when is_list(trace), do: trace
  defp stacktrace(_crash_reason), do: nil

  defp exception_name(%{__struct__: struct}), do: inspect(struct)
  defp exception_name(_), do: "Unknown"
end
