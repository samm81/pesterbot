import Mix.Ecto
import Ecto.Query

defmodule Pesterbot do
  @moduledoc """
  Main Pesterbot application
  """
  use Application

  alias Pesterbot.User
  alias Pesterbot.Repo
  alias Pesterbot.UserSupervisor
  alias Plug.Adapters.Cowboy

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    {port, _} = Integer.parse(System.get_env("PORT") || "4000")

    children = [
      # Define workers and child supervisors to be supervised
      # worker(Pesterbot.Worker, [arg1, arg2, arg3]),
      supervisor(Pesterbot.Repo, []),
      supervisor(Registry, [:unique, :user_registry]),
      supervisor(Pesterbot.UserSupervisor, []),
      worker(
        Task,
        [
          fn ->
            ensure_started(Pesterbot.Repo, [])

            User
            |> select([u], u.uid)
            |> Repo.all()
            |> Enum.map(fn uid ->
              UserSupervisor.create_user_process(uid)
            end)
          end
        ],
        restart: :transient
      ),
      Cowboy.child_spec(:http, Pesterbot.Router, [], port: port)
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pesterbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
