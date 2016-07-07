defmodule Pesterbot do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    { port, _ } = Integer.parse(System.get_env("PORT")||"4000")
    children = [
      # Define workers and child supervisors to be supervised
      # worker(Pesterbot.Worker, [arg1, arg2, arg3]),
      Plug.Adapters.Cowboy.child_spec(:http, Pesterbot.Router, [], [port: port]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pesterbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
