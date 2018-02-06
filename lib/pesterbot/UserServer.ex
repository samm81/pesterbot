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

  @prompt_text "watcha up to"
  @default_messaging_interval 15 * 60 * 1000 # 15 minutes in millis
  @max_messaging_interval 12 * 60 * 60 * 1000 # 12 hours in millis

  defstruct db_entry: %User{},
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

  def prompt_user(user_id) do
    GenServer.cast(via_tuple(user_id), {:prompt_user})
  end

  def get_db_entry(user_id) do
    GenServer.call(via_tuple(user_id), {:db_entry})
  end

  # Server (callbacks)

  def init([user_id]) do
    send(self(), :fetch_data)

    Logger.info("Process created... User ID: #{user_id}")

    {:ok, %__MODULE__{uid: user_id}}
  end

  def handle_call({:respond, message}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call({:send, message_to_user}, _from, state) do
    Router.message_user!(state.uid, message_to_user)
    {:reply, :ok, state}
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

  def handle_cast({:update_user, changeset}, state) do
    new_state = Repo.update!(changeset)
    {:noreply, new_state}
  end

  def handle_cast({:store_message,
    %{"sender" => %{"id" => sender_id},
      "recipient" => %{"id" => recipient_id},
      "timestamp" => timestamp,
      "message" => message_content} = message
  }, state) do
    %{"mid" => message_id,
      "seq" => message_seq } = message_content
    {message_text, quick_reply, nlp} = process_message_content(message_content)
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

  defp process_message_content(
    %{"text" => message_text,
      "quick_reply" => %{ "payload" => payload },
      "nlp" => %{"entities" => entities} } = message_content
  ) do
    {message_text, payload, entities}
  end

  defp process_message_content(
    %{"text" => message_text,
      "nlp" => %{"entities" => entities} } = message_content
  ) do
    {message_text, "", entities}
  end

  defp process_message_content(
    %{"text" => message_text,
      "quick_reply" => %{ "payload" => payload } } = message_content
  ) do
    {message_text, payload, %{}}
  end

  defp process_message_content(
    %{"text" => message_text} = message_content
  ) do
    {message_text, "", %{}}
  end

  def handle_cast(
    {:schedule_next_prompt},
    %__MODULE__{timer_ref: nil} = state
  ) do
    updated_state = schedule_next_prompt_default(state)
    Logger.info("Scheduling next prompt, previous timer_ref was nil, new timer_ref is #{inspect updated_state.timer_ref}")
    {:noreply, updated_state}
  end

  def handle_cast(
    {:schedule_next_prompt},
    %__MODULE__{timer_ref: timer_ref} = state
  ) do
    timer_ref |> Process.cancel_timer
    updated_state = schedule_next_prompt_default(state)
    Logger.info("Scheduling next prompt, previous timer_ref was #{inspect timer_ref}, new timer_ref is #{inspect updated_state.timer_ref}")
    {:noreply, updated_state}
  end

  def handle_cast({:prompt_user}, state) do
    send(self(), :prompt_user)
    {:noreply, state}
  end

  def handle_cast(request, state) do
    super(request, state)
  end

  def handle_info(:fetch_data, %__MODULE__{uid: uid} = state) do
    db_entry = Repo.get_by!(User, uid: uid)
    updated_state = %__MODULE__{state | db_entry: db_entry}

    current_time = (DateTime.utc_now |> DateTime.to_naive)
    Logger.info('db_entry.next_message_timestamp: #{inspect db_entry.next_message_timestamp}')
    Logger.info('current_time: #{inspect current_time}')
    case NaiveDateTime.compare(db_entry.next_message_timestamp, current_time) do
      :gt ->
        Logger.info('next_message_timestamp is in the future, scheduling a prompt at #{inspect db_entry.next_message_timestamp}')
        updated_state = schedule_next_prompt_at(updated_state, db_entry.next_message_timestamp)
      _ -> # :eq and :lt
        Logger.info('next_message_timestamp was in the past, messaging user')
        send(self(), :prompt_user_and_reschedule_default)
    end

    {:noreply, updated_state}
  end

  def handle_info(:prompt_user, state) do
    prompt_user_(state.uid)
    {:noreply, state}
  end

  def handle_info(:prompt_user_and_reschedule_default, state) do
    prompt_user_(state.uid)
    updated_state = schedule_next_prompt_default(state)
    {:noreply, updated_state}
  end

  def handle_info(:prompt_user_and_reschedule_backoff, state) do
    prompt_user_(state.uid)
    updated_state = schedule_next_prompt_backoff(state)
    {:noreply, updated_state}
  end

  defp prompt_user_(uid, prompt_text \\ @prompt_text) do
    arrow_quick_reply = %{
      "content_type" => "text",
      "title" => "^",
      "payload" => "PREVIOUS_REPLY"
    }
    Router.message_user_with_quick_reply!(uid, prompt_text, arrow_quick_reply)
  end

  def handle_info(msg, state) do
    Logger.warn("Received unhandled `handle_info` msg: #{msg}")
    {:noreply, state}
  end

  @doc """
  Creates a timer which will prompt the user after the default messaging interval.
  This should be called when resetting the exponential backoff -
  e.g. when the user messages us back.
  """
  defp schedule_next_prompt_default(state) do
    Logger.info("scheduling next prompt with default message interval #{@default_messaging_interval}")
    schedule_next_prompt_after(state, @default_messaging_interval)
  end

  @doc """
  Looks at the amount of time we waited before prompting the user last time and
  makes that value larger. Then creates a creates a timer that prompts the user
  after this longer amount of time has passed.
  This should be called when we want to prompt the user again, but they haven't
  gotten back to us yet.
  """
  defp schedule_next_prompt_backoff(%__MODULE__{ db_entry: db_entry } = state) do
    new_messaging_interval = db_entry.messaging_interval * 2 |> min(@max_messaging_interval)
    Logger.info("scheduling next prompt, but backing off, previous interval was #{db_entry.messaging_interval} new messaging interval is #{new_messaging_interval}")
    changeset = Ecto.Changeset.change db_entry, messaging_interval: new_messaging_interval
    schedule_next_prompt_after(state, new_messaging_interval, changeset)
  end

  defp schedule_next_prompt_at(%__MODULE__{ db_entry: db_entry } = state, datetime_to_prompt) do
    current_time = (DateTime.utc_now |> DateTime.to_naive)
    millis_from_now = NaiveDateTime.diff(datetime_to_prompt, current_time, :milliseconds)
    schedule_next_prompt_after(state, millis_from_now)
  end

  defp schedule_next_prompt_after(%__MODULE__{ db_entry: db_entry } = state, millis_from_now) do
    {timer_ref, next_message_timestamp} = make_prompt_timer(millis_from_now)
    updated_changeset = Ecto.Changeset.change db_entry, next_message_timestamp: next_message_timestamp
    new_db_entry = Repo.update!(updated_changeset)
    %__MODULE__{state | db_entry: new_db_entry, timer_ref: timer_ref}
  end

  defp schedule_next_prompt_after(%__MODULE__{ db_entry: db_entry } = state, millis_from_now, changeset) do
    {timer_ref, next_message_timestamp} = make_prompt_timer(millis_from_now)
    updated_changeset = Ecto.Changeset.change changeset, next_message_timestamp: next_message_timestamp
    new_db_entry = Repo.update!(updated_changeset)
    %__MODULE__{state | db_entry: new_db_entry, timer_ref: timer_ref}
  end

  defp make_prompt_timer(millis_from_now) do
    timer_ref = Process.send_after(self(), :prompt_user_and_reschedule_backoff, millis_from_now)
    Logger.info("Creating a new timer_ref with reference: #{inspect timer_ref}")
    Logger.info("Will message user in #{millis_from_now} milliseconds")
    now = DateTime.utc_now |> DateTime.to_naive
    next_message_timestamp = NaiveDateTime.add(now, Process.read_timer(timer_ref), :milliseconds)
    Logger.info("next_message_timestamp: #{inspect next_message_timestamp}")
    {timer_ref, next_message_timestamp}
  end

end
