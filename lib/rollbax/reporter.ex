defmodule Rollbax.Reporter do
  @moduledoc """
  Behaviour to be implemented by Rollbax reporters that wish to report `:logger` messages to
  Rollbar. See `Rollbax.LoggerHandler` for more information.

  The Event shape is taken from the 'logger_backends' package as specified here: https://github.com/elixir-lang/logger_backends/blob/master/lib/logger_backend.ex#L15

  The handler should be designed to handle the following events:

  - {level, group_leader, {Logger, message, timestamp, metadata}} where:
    - level is one of :debug, :info, :warn, or :error, as previously described (for compatibility with pre 1.10 backends the :notice will be translated to :info and all messages above :error will be translated to :error)
    - group_leader is the group leader of the process which logged the message
    - {Logger, message, timestamp, metadata} is a tuple containing information about the logged message:
      - the first element is always the atom Logger
      - message is the actual message (as chardata)
      - timestamp is the timestamp for when the message was logged, as a {{year, month, day}, {hour, minute, second, millisecond}} tuple
      - metadata is a keyword list of metadata used when logging the message
  - : flush
  """

  @callback handle_event(type :: term, event :: term) :: Rollbax.Exception.t() | :next | :ignore
end
