defmodule Pesterbot.UserServer do
  use GenServer

  Application.ensure_all_started :timex
  use Timex

  require Logger

  alias Pesterbot.Router
  alias Pesterbot.Repo
  alias Pesterbot.User
  alias Pesterbot.Post

  defstruct db_entry: %{first_name: "", last_name: "", timezone: "", uid: ""},
            uid: "",
            timer_ref: nil

  @default_time_zone Timex.timezone("America/Chicago", DateTime.today)

  # Client

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, [user_id], name: via_tuple(user_id))
  end

  defp via_tuple(user_id) do {:via, Registry, {:user_registry, user_id}} end

  def respond_to_message(user_id, message_from_user) do
    GenServer.cast(via_tuple(user_id), {:schedule_next_prompt})
    GenServer.call(via_tuple(user_id), {:respond, message_from_user})
  end

  def message_user(user_id, message_to_user) do
    GenServer.call(via_tuple(user_id), {:send, message_to_user})
  end

  def read_receipt(user_id) do
    GenServer.cast(via_tuple(user_id), {:read_receipt})
  end

  def get_db_entry(user_id) do
    GenServer.call(via_tuple(user_id), {:db_entry})
  end

  # Server (callbacks)

  def init([user_id]) do
    send(self(), :fetch_data)
    send(self(), :prompt_user)

    Logger.info("Process created... User ID: #{user_id}")

    {:ok, %__MODULE__{ uid: user_id }}
  end

  def handle_call({:respond, message_from_user}, _from, state) do
    response = parse_message(state.uid, message_from_user)
    Router.read_receipt!(state.uid)
    {:reply, response, state}
  end

  def handle_call({:send, message_to_user}, _from, state) do
    response = message_my_user(message_to_user, state.uid)
    {:reply, response, state}
  end

  def handle_call({:db_entry}, _from, state) do
    response = state.db_entry
    {:reply, response, state}
  end

  def handle_call(request, from, state) do
    # Call the default implementation from GenServer
    super(request, from, state)
  end

  def handle_cast({:read_receipt}, state) do
    Router.read_receipt!(state.uid)
  end

  def handle_cast({:schedule_next_prompt}, %__MODULE__{ timer_ref: nil } = state) do
    updated_state = schedule_next_prompt(state)
    Logger.info("Scheduling next prompt, previous timer_ref was nil, new timer_ref is #{updated_state.timer_ref}")
    {:noreply, updated_state}
  end

  def handle_cast({:schedule_next_prompt}, %__MODULE__{ timer_ref: timer_ref } = state) do
    timer_ref |> Process.cancel_timer
    updated_state = schedule_next_prompt(state)
    Logger.info("Scheduling next prompt, previous timer_ref was #{inspect(timer_ref)}, new timer_ref is #{inspect(updated_state.timer_ref)}")
    {:noreply, updated_state}
  end

  def handle_cast(request, state) do
    super(request, state)
  end

  def handle_info(:fetch_data, %__MODULE__{ uid: uid } = state) do
    db_entry = Repo.get_by!(User, uid: uid)
    updated_state = %__MODULE__{ state | db_entry: db_entry }
    {:noreply, updated_state}
  end

  def handle_info(:prompt_user, state) do
    message_my_user("watcha up to", state.uid)
    updated_state = schedule_next_prompt(state) # Reschedule once more
    {:noreply, updated_state}
  end

  def handle_info(msg, state) do
    Logger.warn("Received unhandled `handle_info` msg: #{msg}")
    {:noreply, state}
  end

  # Private Functions

  defp message_my_user(message, uid) do
    Router.message_user!(uid, message)
  end

  defp schedule_next_prompt(state) do
    timer_ref = Process.send_after(self(), :prompt_user, 15 * 60 * 1000) # in 15 minutes
    Logger.info("Creating a new timer_ref with reference: #{inspect(timer_ref)}")
    %__MODULE__{ state | timer_ref: timer_ref }
  end

  defp parse_message(sender_id, %{ "text" => text } ) do
    time_str =
      Timezone.convert(DateTime.now, @default_time_zone)
      |> Timex.format!("{UNIX}")
    Repo.insert!(%Post{uid: sender_id, time: time_str, data: text})
  end

  defp parse_message(sender_id, %{ "attachments" => attachments } ) do
    for attachment <- attachments do
      case attachment do
        %{ "type" => "image", "payload" => %{ "url" => url } } ->
           time_str =
             Timezone.convert(DateTime.now, @default_time_zone)
             |> Timex.format!("{UNIX}")
           Repo.insert!(%Post{uid: sender_id, time: time_str, data: url})
      end
    end
  end

end
