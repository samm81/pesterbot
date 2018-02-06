import Ecto.Query

defmodule Pesterbot.UserSupervisor do
  @moduledoc """
  Supervisor process for UserServers.
  """
  use Supervisor

  require Logger

  alias Pesterbot.UserServer
  alias Pesterbot.Repo
  alias Pesterbot.Router
  alias Pesterbot.User

  @user_registry_name :user_registry

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def find_or_create_user(user_id) do
    if user_exists?(user_id) do
      {:ok, user_id}
    else
      user_id |> create_user_process
    end
  end

  def user_exists?(user_id) do
    case Registry.lookup(@user_registry_name, user_id) do
      [] -> false
      _ -> true
    end
  end

  def create_user_process(user_id) do
    # first we need to check if the user exists in the db
    # TODO should keep a global table of this rather than requerying the db
    user_ids_in_db =
      User
      |> select([u], u.uid)
      |> Repo.all()

    case Enum.any?(user_ids_in_db, fn uid -> uid == user_id end) do
      true ->
        :ok

      false ->
        Logger.info("Inserting a new user into the db, user_id: #{user_id}")
        Repo.insert!(Router.get_user!(user_id))
    end

    case Supervisor.start_child(__MODULE__, [user_id]) do
      {:ok, _pid} -> {:ok, user_id}
      {:error, {:already_started, _pid}} -> {:error, :process_already_exists}
      other -> {:error, other}
    end
  end

  def user_ids do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} ->
      @user_registry_name
      |> Registry.keys(pid)
      |> List.first()
    end)
  end

  def db_entries do
    user_ids()
    |> Enum.map(&UserServer.get_db_entry(&1))
  end

  def init(_) do
    children = [
      worker(UserServer, [], restart: :temporary)
    ]

    # strategy set to `:simple_one_for_one` to handle dynamic child processes.
    supervise(children, strategy: :simple_one_for_one)
  end
end
