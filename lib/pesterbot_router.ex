import IEx

defmodule PesterbotRouter do
  use Plug.Router

  use Plug.Debugger

  Application.ensure_all_started :timex
  use Timex

  alias Pesterbot.Repo

  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], pass: ["text/*"], json_decoder: Poison
  plug :match
  plug :dispatch

  @verifyToken ""
  @pageAccessToken ""
  @sam_id ""
  @user_id_map %{ @sam_id => "sam" }
  @user_timezone_map %{ @sam_id => Timex.timezone("America/Los_Angeles", DateTime.today) }

  def init(opts) do
    subscribe()
    greeting_text()
  end

  get "/webhook" do
    %{ "hub.mode" => "subscribe",
       "hub.challenge" => challenge,
       "hub.verify_token" => @verifyToken } = fetch_query_params(conn).query_params
    send_resp(conn, 200, challenge)
  end

  post "/webhook" do
    case conn.params do
      %{ "object" => "page",
         "entry" => entries } ->
         for entry <- entries do
           case entry do
             %{ "id" => pageid,
                "time" => time,
                "messaging" => messagings } ->
                for messaging <- messagings do
                  case messaging do
                    %{ "delivery" => _ } ->
                      :noop
                    %{ "sender" => %{ "id" => sender_id }, "message" => message } ->
                      IO.puts sender_id
                      case message do
                        %{ "text" => text } ->
                          time = Timezone.convert(DateTime.now, @user_timezone_map[sender_id])
                          time_str = Timex.format!(time, "{UNIX}")
                          write_to_user_file("#{time_str}      #{text}\n", sender_id)
                        %{ "attachments" => attachments } ->
                          for attachment <- attachments do
                            case attachment do
                              %{ "type" => "image", "payload" => %{ "url" => url } } ->
                                 write_to_user_file(url <> "\n", sender_id)
                            end
                          end
                      end
                      read_receipt(sender_id)
                  end
                end
           end
         end
    end

    send_resp(conn, 200, "ok")
  end

  get "/users/:user" do
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
  def fb_send(message) do
    %HTTPoison.Response{ status_code: 200 } =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/me/messages?access_token=" <> @pageAccessToken,
        message,
        %{ "Content-Type" => "application/json" }
      )
  end

  def say(message, user_id) do
    message = Poison.encode!(
      %{ "recipient" => %{ "id" => user_id },
         "message" => %{ "text" => message } }
    )
    fb_send(message)
  end

  def read_receipt(user_id) do
    read_receipt = Poison.encode!(
      %{ "recipient" => %{ "id" => user_id },
         "sender_action" => "mark_seen" }
    )
    fb_send(read_receipt)
  end

  def say_test do
    say("watcha up to", @sam_id)
  end

  def greeting_text do
    message = Poison.encode!(
      %{ "setting_type" => "greeting",
         "greeting" => %{ "text": "what's up boss" }
       }
    )
    %HTTPoison.Response{ status_code: 200 } =
      HTTPoison.post!(
        "https://graph.facebook.com/v2.6/me/thread_settings?access_token=" <> @pageAccessToken,
        message,
        %{ "Content-Type" => "application/json" }
      )
  end

  def subscribe do
    %HTTPoison.Response{ status_code: 200, body: "{\"success\":true}" } =
      HTTPoison.post!("https://graph.facebook.com/v2.6/me/subscribed_apps?access_token=" <> @pageAccessToken, "")
  end

  def write_to_user_file(message, user_id) do
    user = @user_id_map[user_id]
    case File.open(user, [:write, :append, :utf8]) do
      {:ok, user_file} ->
        IO.write(user_file, message)
      {:error, :enoent} ->
        File.touch(user)
        write_to_user_file(message, user_id)
    end
  end

end
