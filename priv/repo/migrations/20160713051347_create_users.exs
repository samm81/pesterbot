defmodule Pesterbot.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :uid, :string
      add :first_name, :string
      add :last_name, :string
      add :timezone, :string
      timestamps()
    end
  end
end
