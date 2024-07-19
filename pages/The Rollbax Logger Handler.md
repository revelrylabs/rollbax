  ### Rollbax Logger Handler
  
  An Erlang :logger handler that passes log events to Rollbax reporters for sending to Rollbar.

  ### Why

  In Elixir and Erlang, crashes and exits from GenServers and other processes are reported through
  the `:logger` module. This module can be added as a `:logger` handler to process logged events. It will check the configured
  `:reporters` and send any relevant events to those reporters for submission to Rollbar.

  The reporters implement the `Rollbax.Reporter` behaviour. Every message received by
  `Rollbax.LoggerHandler` is run through the list of reporters and the behaviour is determined by
  the return value of each reporter's `Rollbax.Reporter.handle_event/2` callback:

  - When the callback returns a `Rollbax.Exception` struct, the exception is reported to Rollbar
    and no other reporters are called

  - When the callback returns `:next`, the reporter is skipped and it moves on to the next reporter

  - When the callback returns `:ignore`, the reported message is ignored and no more reporters are
    tried

  ### Key Points:

  - To use this, You must configure the `:rollbax` application with: `config :rollbax, :enable_crash_reports, true`

  - The `:reporters` can also be configured, defaulting to `[Rollbax.Reporter.Standard]`.

  - It requires the `:reporters` option to be configured, which should be a list of module names that implement the `Rollbax.Reporter` behaviour.

  - On initialization, it will validate the provided configuration.

  - On config updates, it will re-validate the configuration to make sure Rollbax can still function properly.

  - The `log/2` callback handles the actual logging event by checking the `:reporters` config and running each one.

  ### Summary

  1. This module can be added as a `:logger` handler
  2. Log events come in to the `log/2` callback
  3. It checks the configured reporters
  4. Events are passed to the reporters for possible submission to Rollbar
  5. Depending on the response, the event is either reported to Rollbar, the event is passed to the next reporter, or the event is ignored

  This allows customizing and processing of events via reporters before sending to Rollbar.

  More information on configuring reporters can be found in the `Rollbax` module docs.