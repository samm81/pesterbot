defmodule Pesterbot.User do
  @moduledoc """
  Defines the User schema.
  """
  use Ecto.Schema

  schema "users" do
    field(:uid, :string)
    field(:first_name, :string)
    field(:last_name, :string)
    field(:next_message_timestamp, :naive_datetime)
    field(:messaging_interval, :integer)
    field(:timezone, :string)
    timestamps()
  end
end
