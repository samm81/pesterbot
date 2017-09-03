defmodule Pesterbot.UserServer do
  @moduledoc """
  Implements the storage and interaction mechanisms for a user.
  """
  use GenServer

  require Logger

  alias Pesterbot.Router
  alias Pesterbot.Repo
  alias Pesterbot.User
  alias Pesterbot.Message

  defstruct db_entry: %{first_name: "", last_name: "", timezone: "", uid: ""},
            uid: "",
            timer_ref: nil

  # Client

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, [user_id], name: via_tuple(user_id))
  end

  defp via_tuple(user_id) do {:via, Registry, {:user_registry, user_id}} end

  def handle_message(user_id, message) do
    user = via_tuple(user_id)
    GenServer.cast(user, {:schedule_next_prompt})
    GenServer.cast(user, {:store_message, message})
    GenServer.cast(user, {:read_receipt})
    GenServer.call(user, {:respond, message})
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

    {:ok, %__MODULE__{uid: user_id}}
  end

  def handle_call({:respond, message}, _from, state) do
    response = ""
    {:reply, response, state}
  end

  def handle_call({:send, message_to_user}, _from, state) do
    Router.message_user!(state.uid, message_to_user)
    response = ""
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
    {:noreply, state}
  end

  def handle_cast({:store_message, message}, state)  do
    %{"sender" => %{"id" => sender_id},
      "recipient" => %{"id" => recipient_id},
      "timestamp" => timestamp,
      "message" => message_} = message
    message_ = Map.merge(%{"text" => ""}, message_)
    message_ = Map.merge(%{"quick_reply" => ""}, message_)
    %{"mid" => message_id,
      "seq" => message_seq,
      "text" => message_text,
      "quick_reply" => quick_reply} = message_
    timestamp = round(timestamp / 1000)
    json_message = Poison.encode!(message)
    Repo.insert!(
      %Message{sender_id: sender_id,
                recipient_id: recipient_id,
                timestamp: timestamp,
                message_id: message_id,
                message_seq: message_seq,
                message_text: message_text,
                quick_reply: quick_reply,
                json_message: json_message}
    )
    {:noreply, state}
  end

  def handle_cast(
    {:schedule_next_prompt},
    %__MODULE__{timer_ref: nil} = state
  ) do
    updated_state = schedule_next_prompt(state)
    Logger.info("Scheduling next prompt, previous timer_ref was nil, new timer_ref is #{updated_state.timer_ref}")
    {:noreply, updated_state}
  end

  def handle_cast(
    {:schedule_next_prompt},
    %__MODULE__{timer_ref: timer_ref} = state
  ) do
    timer_ref |> Process.cancel_timer
    updated_state = schedule_next_prompt(state)
    Logger.info("Scheduling next prompt, previous timer_ref was #{inspect(timer_ref)}, new timer_ref is #{inspect(updated_state.timer_ref)}")
    {:noreply, updated_state}
  end

  def handle_cast(request, state) do
    super(request, state)
  end

  def handle_info(:fetch_data, %__MODULE__{uid: uid} = state) do
    db_entry = Repo.get_by!(User, uid: uid)
    updated_state = %__MODULE__{state | db_entry: db_entry}
    {:noreply, updated_state}
  end

  def handle_info(:prompt_user, state) do
    Router.message_user!(state.uid, "watcha up to")
    updated_state = schedule_next_prompt(state) # Reschedule once more
    {:noreply, updated_state}
  end

  def handle_info(msg, state) do
    Logger.warn("Received unhandled `handle_info` msg: #{msg}")
    {:noreply, state}
  end

  # Private Functions

  defp schedule_next_prompt(state) do
    # in 15 minutes
    timer_ref = Process.send_after(self(), :prompt_user, 15 * 60 * 1000)
    Logger.info("Creating a new timer_ref with reference: #{inspect(timer_ref)}")
    %__MODULE__{state | timer_ref: timer_ref}
  end

end
