use Mix.Config

config :ex_unit,
  assert_receive_timeout: 800,
  refute_receive_timeout: 200

config :logger, :default_handler, false

config :rollbax, :logger, [
  {
    :handler,
    :rollbax_handler,
    Rollbax.Logger,
    %{
      config: %{
      },
      formatter: Logger.Formatter.new()
    }
  }
]

config :logger, Rollbax.Logger,
  :discard_threshold_periodic_check
