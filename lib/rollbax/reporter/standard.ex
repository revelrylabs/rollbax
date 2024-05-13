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

  defp format_exception(
         ["GenServer ", pid, " terminating", details | last_message_parts] = msg,
         meta
       ) do
    last_message = gen_server_last_message(last_message_parts)

    # TODO: maybe need to figure out how to extract the last message, too?
    case meta[:crash_reason] do
      {exception, stacktrace}
      when is_list(stacktrace) and is_exception(exception) ->
        %Rollbax.Exception{
          class: "GenServer terminating (#{exception_name(exception)})",
          message: Exception.message(exception),
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid,
            "last_message" => last_message
          }
        }

      {:stop_reason, []} ->
        %Rollbax.Exception{
          class: "GenServer terminating (stop)",
          message: IO.iodata_to_binary(msg),
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid,
            "last_message" => last_message
          }
        }

      _other ->
        exception_message =
          case details do
            [[_prefix | message] | _] -> message
            _ -> "Unknown Exception"
          end

        %Rollbax.Exception{
          class: "GenServer terminating",
          message: exception_message,
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => pid,
            "last_message" => last_message
          }
        }
    end
  end

  defp format_exception(
         ["Task " <> _ = _error, details | function_details] = _msg,
         meta
       ) do
    {function, args} = parse_function_and_args(function_details)

    case meta[:crash_reason] do
      {exception, stacktrace}
      when is_list(stacktrace) and is_exception(exception) ->
        %Rollbax.Exception{
          class: "Task terminating (#{exception_name(exception)})",
          message: Exception.message(exception),
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => inspect(meta[:pid]),
            "started_from" => inspect(hd(meta[:callers] || [])),
            "function" => function,
            "arguments" => args
          }
        }

      _other ->
        exception_message =
          case details do
            [[_prefix | message] | _] -> message
            _ -> "Unknown Exception"
          end

        %Rollbax.Exception{
          class: "Task terminating",
          message: exception_message,
          stacktrace: stacktrace(meta[:crash_reason]),
          custom: %{
            "name" => inspect(meta[:pid]),
            "started_from" => inspect(hd(meta[:callers] || [])),
            "function" => function,
            "arguments" => args
          }
        }
    end
  end

  defp format_exception(
         ["Process ", pid, " raised an exception" | error_details],
         meta
       ) do
    {message, name} =
      case meta[:crash_reason] do
        {exception, stacktrace} when is_exception(exception) and is_list(stacktrace) ->
          {Exception.message(exception), inspect(exception.__struct__)}

        _ ->
          {IO.iodata_to_binary(error_details), "Unknown Exception"}
      end

    %Rollbax.Exception{
      class: "error in process (#{name})",
      message: message,
      stacktrace: stacktrace(meta[:crash_reason]),
      custom: %{
        "pid" => pid
      }
    }
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

  defp gen_server_last_message(["\nLast message", _list, ": " | rest] = _message_parts) do
    IO.iodata_to_binary(rest)
  rescue
    _ -> nil
  end

  defp gen_server_last_message([_first | rest] = _message_parts),
    do: gen_server_last_message(rest)

  defp gen_server_last_message(_), do: nil

  defp parse_function_and_args(["\nFunction: " <> function, args | _rest] = _message_parts) do
    parsed_args = String.replace(args, ~r/^\s*Args: /, "")
    {function, parsed_args}
  rescue
    _ -> {nil, nil}
  end

  defp parse_function_and_args([_first | rest] = _message_parts),
    do: parse_function_and_args(rest)

  defp parse_function_and_args(_), do: {nil, nil}
end
