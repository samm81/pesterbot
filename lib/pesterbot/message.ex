defmodule Pesterbot.Message do
  use Ecto.Schema

  schema "messages" do
    field :sender_id, :string
    field :recipient_id, :string
    field :timestamp, :integer
    field :message_id, :string
    field :message_seq, :integer
    field :message_text, :string
    field :quick_reply, :string
    field :json_message, :string
    timestamps()
  end
end
