import IEx

defmodule Pesterbot.Router do
  use Plug.Router

  use Plug.Debugger

  Application.ensure_all_started :timex
  use Timex

  alias Pesterbot.Repo

  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], pass: ["text/*"], json_decoder: Poison
  plug :match
  plug :dispatch

  @app_id System.get_env("APP_ID")
  @app_secret System.get_env("APP_SECRET")
  @page_access_token System.get_env("PAGE_ACCESS_TOKEN")

  @verify_token System.get_env("VERIFY_TOKEN")

  #@sam_id System.get_env("SAM_ID")
  #@user_id_map %{ @sam_id => "sam" }
  #@user_timezone_map %{ @sam_id => Timex.timezone("America/Los_Angeles", DateTime.today) }

  @default_time_zone Timex.timezone("America/Los_Angeles", DateTime.today)

  @users_file "registered_users"

  def init(opts) do
    subscribe()
    greeting_text!()
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

  def parse_entry( %{ "id" => pageid, "time" => time, "messaging" => messagings } ) do
    for messaging <- messagings do
      parse_messaging(messaging)
    end
  end

  def parse_messaging( %{ "delivery" => _ } ), do: :noop
  def parse_messaging( %{ "sender" => %{ "id" => sender_id }, "message" => message } ) do
    registered_users =
      File.read!(@users_file)
      |> String.split("\n")
    case Enum.any?(registered_users, fn(user) -> user == sender_id end) do
      true -> :ok
      false -> File.open!(@users_file, [:write, :append, :utf8]) |> IO.write("\n" <> sender_id)
    end

    parse_message(sender_id, message)
    read_receipt!(sender_id)
  end

  def parse_message(sender_id, %{ "text" => text } ) do
    #time = Timezone.convert(DateTime.now, @user_timezone_map[sender_id])
    time_str =
      Timezone.convert(DateTime.now, @default_time_zone)
      |> Timex.format!("{UNIX}")
    write_to_user_file("#{time_str}      #{text}\n", sender_id)
  end

  def parse_message(sender_id, %{ "attachments" => attachments } ) do
    for attachment <- attachments do
      case attachment do
        %{ "type" => "image", "payload" => %{ "url" => url } } ->
           write_to_user_file(url <> "\n", sender_id)
      end
    end
  end

  get "/users/:user" do
    user = "users/" <> user
    page =
      case File.read(user) do
        {:ok, contents} ->
          contents
        {:error, :enoent} ->
          "user #{user} not available!"
      end
    send_resp(conn, 200, page)
  end

  match _ do
    IO.puts "unrecognized route"
    IO.puts inspect conn
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

  def say!(message, user_id) do
    Poison.encode!( %{
      "recipient" => %{ "id" => user_id },
      "message" => %{ "text" => message }
    }) |> fb_send!
  end

  def read_receipt!(user_id) do
    Poison.encode!( %{
      "recipient" => %{ "id" => user_id },
      "sender_action" => "mark_seen"
    }) |> fb_send!
  end

  def pester_users! do
    user_ids =
      File.read!(@users_file)
      |> String.split("\n")
    for user_id <- user_ids do
      case say!("watcha up to", user_id) do
        %HTTPoison.Response{ status_code: 200 } -> :ok
        %HTTPoison.Response{ status_code: 400 } -> :err
      end
    end
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

  def write_to_user_file(message, user_id) do
    #user = @user_id_map[user_id]
    user = "users/" <> user_id
    case File.open(user, [:write, :append, :utf8]) do
      { :ok, user_file } ->
        IO.write(user_file, message)
      { :error, :enoent } ->
        case File.exists?("users") do
          false -> File.mkdir!("users")
          true -> :ok
        end
        File.touch(user)
        write_to_user_file(message, user_id)
    end
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
      HTTPoison.post!("https://graph.facebook.com/v2.6/1569233543371008/subscriptions?" <> params, "")
  end

end
