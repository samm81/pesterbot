defmodule Pesterbot.Message do
  @moduledoc """
  Defines the Message schema. Corresponds to a message object in the facebook
  webhook API:
  developers.facebook.com/docs/messenger-platform/webhook-reference/message
  """
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
