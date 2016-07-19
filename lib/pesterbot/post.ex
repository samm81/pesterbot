defmodule Pesterbot.Post do
  use Ecto.Schema

  schema "posts" do
    field :uid, :string
    field :time, :string
    field :data, :string
    timestamps
  end
end
