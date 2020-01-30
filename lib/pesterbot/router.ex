import Ecto.Query

defmodule Pesterbot.Router do
  @moduledoc """
  Handles all incoming and outgoing HTTP requests
  """
  use Plug.Router
  use Plug.Debugger

  Application.ensure_all_started(:timex)
  use Timex

  require Logger

  alias Plug.Conn
  alias Pesterbot.{Repo, User, Message, UserSupervisor, UserServer}

  plug(Plug.Logger)
  plug(Plug.Parsers, parsers: [:json], pass: ["text/*"], json_decoder: Poison)
  plug(:match)
  plug(:dispatch)

  @app_id System.get_env("APP_ID")
  @app_secret System.get_env("APP_SECRET")
  @page_access_token System.get_env("PAGE_ACCESS_TOKEN")

  @verify_token System.get_env("VERIFY_TOKEN")

  @default_time_zone "America/Chicago"

  @page_size 500

  def init(_opts) do
    # subscribe()
    # greeting_text!()
  end

  get "/webhook" do
    %{
      "hub.mode" => "subscribe",
      "hub.challenge" => challenge,
      "hub.verify_token" => @verify_token
    } = fetch_query_params(conn).query_params

    send_resp(conn, 200, challenge)
  end

  post "/webhook" do
    Logger.info("/webhook conn.params #{inspect(conn.params)}")
    parse_webhook_params(conn.params)

    send_resp(conn, 200, "ok")
  end

  def parse_webhook_params(%{"object" => "page", "entry" => entries}) do
    for entry <- entries do
      parse_entry(entry)
    end
  end

  def parse_entry(%{
        "id" => _pageid,
        "time" => _time,
        "messaging" => messages
      }) do
    for message <- messages do
      parse_message(message)
    end
  end

  def parse_message(%{"delivery" => _}), do: :noop

  def parse_message(%{"sender" => %{"id" => sender_id}} = message) do
    # Ensure that the user has an associated UserServer
    {:ok, _} = UserSupervisor.find_or_create_user(sender_id)
    UserServer.handle_message(sender_id, message)
  end

  get "/users" do
    page =
      UserSupervisor.db_entries()
      |> Enum.map(fn %User{first_name: first_name, last_name: last_name, uid: uid} ->
        "<a href='/users/" <> uid <> "'>" <> first_name <> " " <> last_name <> "</a>"
      end)
      |> Enum.join("<br/><br/>")

    page =
      ~s(<html><head><meta charset="utf-8"></head><body style="font:monospace">) <>
        page <> ~s(</body></html>)

    send_resp(conn, 200, page)
  end

  get "/users/:uid" do
    params = fetch_query_params(conn).query_params
    dump_messages_as_html(conn, uid, params)
  end

  def dump_messages_as_html(conn, uid, %{"page" => pagestr}) do
    case Integer.parse(pagestr) do
      {page, _remainder} ->
        offset = @page_size * (page - 1)

        messages =
          Repo.all(
            from(
              message in Message,
              where: message.sender_id == ^uid,
              order_by: [desc: message.timestamp],
              limit: @page_size,
              offset: ^offset,
              select: map(message, [:timestamp, :message_text])
            )
          )

        format_messages_as_html(conn, uid, messages)

      :error ->
        send_resp(conn, 400, "page param #{pagestr} invalid, does not parse to integer")
    end
  end

  def dump_messages_as_html(conn, uid, %{}) do
    messages =
      Repo.all(
        from(
          message in Message,
          where: message.sender_id == ^uid,
          order_by: [desc: message.timestamp],
          select: map(message, [:timestamp, :message_text])
        )
      )

    format_messages_as_html(conn, uid, messages)
  end

  def format_messages_as_html(conn, uid, messages) do
    page =
      case messages do
        [] ->
          "user #{uid} not available, or page param is too large"

        _ ->
          messages
          |> Enum.map(fn message ->
            datetime = Timex.from_unix(message.timestamp)
            datetime = datetime |> Timex.to_datetime(@default_time_zone)

            datetime =
              case datetime do
                %Timex.AmbiguousDateTime{} -> datetime.after
                %DateTime{} -> datetime
                _ -> :error
              end

            {:ok, dt_str} = datetime |> Timex.format("{UNIX}")
            dt_str <> "\t" <> message.message_text
          end)
          |> Enum.join("<br/>")
      end

    page =
      ~s(<html><head><meta charset="utf-8"></head><body style="font-family: monospace;"><div>) <>
        page <> ~s(</div></body></html>)

    page =
      page
      |> String.replace(
        "\t",
        "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
      )

    send_resp(conn, 200, page)
  end

  post "/broadcast" do
    case conn.host do
      "localhost" ->
        {:ok, "message=" <> message, _} = Conn.read_body(conn)

        message_all_users!(message)
        send_resp(conn, 200, "ok")

      _ ->
        send_resp(conn, 400, "oops")
    end
  end

  get "/" do
    send_resp(conn, 200, "go to /users to see the list of users")
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  HTTPoison.start()

  def fb_send!(message) do
    HTTPoison.post!(
      "https://graph.facebook.com/v3.2/me/messages?access_token=" <> @page_access_token,
      message,
      %{"Content-Type" => "application/json"}
    )
  end

  def read_receipt!(user_id) do
    message =
      Poison.encode!(%{
        "recipient" => %{"id" => user_id},
        "sender_action" => "mark_seen"
      })

    message |> fb_send!
  end

  def message_user_with_quick_reply!(user_id, message, quick_reply) do
    message =
      Poison.encode!(%{
        "recipient" => %{"id" => user_id},
        "messaging_type" => "UPDATE",
        "message" => %{
          "text" => message,
          quick_replies: [quick_reply]
        }
      })

    message |> fb_send!
  end

  def message_user!(user_id, message) do
    message =
      Poison.encode!(%{
        "recipient" => %{"id" => user_id},
        "messaging_type" => "UPDATE",
        "message" => %{
          "text" => message
        }
      })

    message |> fb_send!
  end

  def message_users!(user_ids, message) do
    user_ids
    |> Enum.map(fn user_id -> message_user!(user_id, message) end)
  end

  def message_all_users!(message) do
    User
    |> select([u], u.uid)
    |> Repo.all()
    |> message_users!(message)
  end

  def pester_users! do
    message_all_users!("watcha up to")
  end

  def greeting_text! do
    message =
      Poison.encode!(%{
        "setting_type" => "greeting",
        "greeting" => %{text: "what's up boss"}
      })

    %HTTPoison.Response{status_code: 200} =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/me/thread_settings?access_token=" <> @page_access_token,
        message,
        %{"Content-Type" => "application/json"}
      )
  end

  def subscribe do
    %HTTPoison.Response{status_code: 200, body: ~s({"success":true})} =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/me/subscribed_apps?access_token=" <> @page_access_token,
        ""
      )
  end

  def get_ngrok_url do
    %HTTPoison.Response{status_code: 200, body: body} =
      HTTPoison.get!("localhost:4040/api/tunnels")

    %{"tunnels" => [%{"public_url" => url}]} = Poison.decode!(body)
    url
  end

  def publish_webhook!(ngrok_url) do
    params =
      URI.encode_query(%{
        "object" => "page",
        "verify_token" => @verify_token,
        "callback_url" => ngrok_url <> "/webhook",
        "access_token" => @app_id <> "|" <> @app_secret
      })

    %HTTPoison.Response{status_code: 200, body: ~s({"success":true})} =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/" <> @app_id <> "/subscriptions?" <> params,
        ""
      )
  end

  def get_user!(user_id) do
    %HTTPoison.Response{status_code: 200, body: body} =
      HTTPoison.get!(
        "https://graph.facebook.com/v2.6/" <> user_id <> "?access_token=" <> @page_access_token
      )

    user = Poison.decode!(body)

    %User{
      first_name: user["first_name"],
      last_name: user["last_name"],
      timezone: Integer.to_string(user["timezone"]),
      uid: user_id
    }
  end
end
