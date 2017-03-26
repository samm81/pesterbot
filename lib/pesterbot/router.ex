import Ecto.Query

defmodule Pesterbot.Router do
  use Plug.Router

  use Plug.Debugger

  alias Pesterbot.Repo
  alias Pesterbot.User
  alias Pesterbot.Post
  alias Pesterbot.UserSupervisor
  alias Pesterbot.UserServer

  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], pass: ["text/*"], json_decoder: Poison
  plug :match
  plug :dispatch

  @app_id System.get_env("APP_ID")
  @app_secret System.get_env("APP_SECRET")
  @page_access_token System.get_env("PAGE_ACCESS_TOKEN")

  @verify_token System.get_env("VERIFY_TOKEN")

  def init(_opts) do
    #subscribe()
    #greeting_text!()
  end

  get "/webhook" do
    %{ "hub.mode" => "subscribe",
       "hub.challenge" => challenge,
       "hub.verify_token" => @verify_token } = fetch_query_params(conn).query_params
    send_resp(conn, 200, challenge)
  end

  post "/webhook" do
    parse_webhook_params(conn.params)

    send_resp(conn, 200, "ok")
  end

  def parse_webhook_params( %{ "object" => "page", "entry" => entries } ) do
    for entry <- entries do
      parse_entry(entry)
    end
  end

  def parse_entry( %{ "id" => _pageid, "time" => _time, "messaging" => messagings } ) do
    for messaging <- messagings do
      parse_messaging(messaging)
    end
  end

  def parse_messaging( %{ "delivery" => _ } ), do: :noop

  def parse_messaging( %{ "sender" => %{ "id" => sender_id }, "message" => message } ) do
    # Ensure that the user has an associated UserServer
    {:ok, _} = UserSupervisor.find_or_create_user(sender_id)
    UserServer.respond_to_message(sender_id, message)
  end

  get "/users" do
    page =
      UserSupervisor.db_entries
      |> Enum.map( fn %User{ first_name: first_name, last_name: last_name, uid: uid } ->
        "<a href='/users/" <> uid <> "'>" <> first_name <> " " <> last_name <> "</a>"
      end) |> Enum.join("<br/><br/>")
    page = "<html><head><meta charset=\"utf-8\"></head><body style\"font:Courier New\">" <> page <> "</body></html>"
    send_resp(conn, 200, page)
  end

  get "/users/:uid" do
    posts =
      Repo.all(from post in Post,
               where: post.uid == ^uid,
               order_by: post.inserted_at,
               select: map(post, [:time, :data]))
    page =
      case posts do
        [] -> "user #{uid} not available!"
        _ ->
          posts
          |> Enum.map(fn(post) -> post.time <> "\t" <> post.data end)
          |> Enum.join("<br/>")
      end
    page = "<html><head><meta charset=\"utf-8\"></head><body style\"font:Courier New\">" <> page <> "</body></html>"
    |> String.replace("\t", "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;")

    send_resp(conn, 200, page)
  end

  post "/broadcast" do
    case conn.host do
      "localhost" ->
        { :ok, "message=" <> message, _ } =
          Plug.Conn.read_body(conn)

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

  HTTPoison.start

  def fb_send!(message) do
    HTTPoison.post!(
      "https://graph.facebook.com/v2.6/me/messages?access_token=" <> @page_access_token,
      message,
      %{ "Content-Type" => "application/json" }
    )
  end

  def read_receipt!(user_id) do
    Poison.encode!( %{
      "recipient" => %{ "id" => user_id },
      "sender_action" => "mark_seen"
    }) |> fb_send!
  end

  def message_user!(user_id, message) do
    Poison.encode!( %{
      "recipient" => %{ "id" => user_id },
      "message" => %{ "text" => message }
    }) |> fb_send!
  end

  def message_users!(user_ids, message) do
    user_ids
    |> Enum.map(fn(user_id) -> message_user!(user_id, message) end)
  end

  def message_all_users!(message) do
    Repo.all(from user in User,
             select: user.uid)
    |> message_users!(message)
  end

  def pester_users! do
    message_all_users!("watcha up to")
  end

  def greeting_text! do
    message = Poison.encode!( %{
      "setting_type" => "greeting",
      "greeting" => %{ "text": "what's up boss" }
    })
    %HTTPoison.Response{ status_code: 200 } =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/me/thread_settings?access_token=" <> @page_access_token,
        message,
        %{ "Content-Type" => "application/json" }
      )
  end

  def subscribe do
    %HTTPoison.Response{ status_code: 200, body: "{\"success\":true}" } =
      HTTPoison.post!("https://graph.facebook.com/v2.6/me/subscribed_apps?access_token=" <> @page_access_token, "")
  end

  def get_ngrok_url do
    %HTTPoison.Response{ status_code: 200, body: body } =
      HTTPoison.get!("localhost:4040/api/tunnels")
    %{ "tunnels" => [ %{ "public_url" => url } ] } = Poison.decode!(body)
    url
  end

  def publish_webhook!(ngrok_url) do
    params = URI.encode_query( %{
        "object" => "page",
        "verify_token" => @verify_token,
        "callback_url" => ngrok_url <> "/webhook",
        "access_token" => @app_id <> "|" <> @app_secret
    })
    %HTTPoison.Response{ status_code: 200, body: "{\"success\":true}" } =
      HTTPoison.post!("https://graph.facebook.com/v2.6/" <> @app_id <> "/subscriptions?" <> params, "")
  end

  def get_user!(user_id) do
    %HTTPoison.Response{ status_code: 200, body: body } =
      HTTPoison.get!("https://graph.facebook.com/v2.6/" <> user_id <> "?access_token=" <> @page_access_token)
    user = Poison.decode!(body)
    %User{first_name: user["first_name"], last_name: user["last_name"], timezone: Integer.to_string(user["timezone"]), uid: user_id}
  end

end
