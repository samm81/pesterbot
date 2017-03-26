defmodule Pesterbot.User do
  use Ecto.Schema

  schema "users" do
    field :uid, :string
    field :first_name, :string
    field :last_name, :string
    field :timezone, :string
    timestamps()
  end
end
