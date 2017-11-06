defmodule Pesterbot.Repo.Migrations.AddTimerStateToUser do

  @default_messaging_interval 15 * 60 * 1000 # 15 minutes in millis

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :next_message_timestamp, :naive_datetime
      add :messaging_interval, :integer, default: @default_messaging_interval
    end
  end
end
