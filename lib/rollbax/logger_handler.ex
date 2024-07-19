defmodule Rollbax.LoggerHandler do
  @moduledoc """
  An Erlang :logger handler that passes the actual Rollbax logging to its configured reporters

  # TODO: explain how this works with configs and reporters and everything else...
          see the moduledoc on the old Rollbax.Logger module

          also need to fix up mix.exs and versioning, as well as check the rest of the docs
  """

  @doc """
  Handle a log message
  """
  def log(event, %{reporters: reporters}) when is_list(reporters) do
    run_reporters(reporters, event)
  end

  @doc """
  Handle initialization by making sure we have a valid config
  """
  def adding_handler(config) do
    {:ok, initialize_config(config)}
  end

  @doc """
  Handle updated config by making sure the internal portion is valid
  """
  def changing_config(:update, _old_config, new_config) do
    {:ok, initialize_config(new_config)}
  end

  @doc """
  Create a valid Rollbax.LoggerHandler config by filling in any missing options
  """
  def initialize_config(existing) do
    existing
    |> Map.put_new(:reporters, [Rollbax.Reporter.Standard])
    |> Map.put_new(:initialized, true)
  end


  defp run_reporters([reporter | rest], %{level: level, meta: meta, msg: {:string, msg}} = event) do
    case reporter.handle_event(level, {Logger, msg, meta[:time], meta}) do
      %Rollbax.Exception{} = exception ->
        Rollbax.report_exception(exception)

      :next ->
        run_reporters(rest, event)

      :ignore ->
        :ok
    end
  end

  defp run_reporters([_ | _], event) do
    # remove or convert to a Logger message after this has been tested extensively
    IO.inspect(event, label: "UNHANDLED EVENT SHAPE")
    :error
  end

  # If no reporter ignored or reported this event, then we're gonna report this
  # as a Rollbar "message" with the same logic that Logger uses to translate
  # messages (so that it will have Elixir syntax when reported).
  defp run_reporters([], _event) do
    :ok
  end
end
