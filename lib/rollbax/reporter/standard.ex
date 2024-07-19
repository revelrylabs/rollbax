defmodule Rollbax.Reporter.Standard do
  @moduledoc """
  A `Rollbax.Reporter` that translates crashes and exits from processes to nicely-formatted
  Rollbar exceptions.
  """

  @behaviour Rollbax.Reporter

  def handle_event(:error, {_Logger, msg, _timestamp, meta}) do
    # msg = List.first(msg)
    format_exception(msg, meta)
  end

  def handle_event(_level, _event) do
    :next
  end

  defp format_exception(
         ["GenServer ", pid, " terminating", details | last_message_parts] = msg,
         meta
       ) do
    last_message = parse_last_message(last_message_parts)
    {class, message} = parse_exception(meta[:crash_reason], details, msg)

    %Rollbax.Exception{
      class: full_class("GenServer terminating", class),
      message: message,
      stacktrace: stacktrace(meta[:crash_reason]),
      custom: %{
        "name" => pid,
        "last_message" => last_message
      }
    }
  end

  defp format_exception(
         [
           ":gen_event handler ",
           module,
           " installed in ",
           _pid,
           " terminating",
           details | last_message_parts
         ] = msg,
         meta
       ) do
    last_message = parse_last_message(last_message_parts)
    {class, message} = parse_exception(meta[:crash_reason], details, msg)

    %Rollbax.Exception{
      class: full_class("gen_event handler terminating", class),
      message: message,
      stacktrace: stacktrace(meta[:crash_reason]),
      custom: %{
        "name" => module,
        "manager" => inspect(meta[:pid]),
        "last_message" => last_message
      }
    }
  end

  defp format_exception(
         ["Task " <> _ = _error, details | function_details] = msg,
         meta
       ) do
    {function, args} = parse_function_and_args(function_details)
    {class, message} = parse_exception(meta[:crash_reason], details, msg)

    %Rollbax.Exception{
      class: full_class("Task terminating", class),
      message: message,
      stacktrace: stacktrace(meta[:crash_reason]),
      custom: %{
        "name" => inspect(meta[:pid]),
        "started_from" => inspect(hd(meta[:callers] || [])),
        "function" => function,
        "arguments" => args
      }
    }
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

  # ignore other messages, such as those logged directly by the application
  defp format_exception(_msg, _meta) do
    IO.inspect("or am I here")
    :next
  end

  defp stacktrace({_, trace} = _crash_reason) when is_list(trace), do: trace
  defp stacktrace(_crash_reason), do: nil

  defp exception_name(%{__struct__: struct}), do: inspect(struct)
  defp exception_name(_), do: "Unknown"

  defp parse_last_message(["\nLast message", _list, ": " | rest] = _message_parts) do
    IO.iodata_to_binary(rest)
  rescue
    _ -> nil
  end

  defp parse_last_message(["\nLast message: ", message] = _message_parts) do
    message
  end

  defp parse_last_message([_first | rest] = _message_parts),
    do: parse_last_message(rest)

  defp parse_last_message(_), do: nil

  defp parse_function_and_args(["\nFunction: " <> function, args | _rest] = _message_parts) do
    parsed_args = String.replace(args, ~r/^\s*Args: /, "")
    {function, parsed_args}
  rescue
    _ -> {nil, nil}
  end

  defp parse_function_and_args([_first | rest] = _message_parts),
    do: parse_function_and_args(rest)

  defp parse_function_and_args(_), do: {nil, nil}

  defp parse_exception({exception, stacktrace} = _crash_reason, _error_details, _full_msg)
       when is_list(stacktrace) and is_exception(exception) do
    {
      exception_name(exception),
      Exception.message(exception)
    }
  end

  defp parse_exception({:stop_reason, []} = _crash_reason, _error_details, full_msg) do
    {
      "stop",
      IO.iodata_to_binary(full_msg)
    }
  end

  defp parse_exception(_crash_reason, error_details, _full_msg) do
    exception_message =
      case error_details do
        [[_prefix | message] | _] -> message
        _ -> "Unknown Exception"
      end

    {"", exception_message}
  end

  defp full_class(base, "" = _suffix), do: base

  defp full_class(base, suffix), do: "#{base} (#{suffix})"
end
