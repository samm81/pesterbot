defmodule Pesterbot.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :uid, :string
      add :time, :string
      add :data, :text
      timestamps()
    end
  end
end
