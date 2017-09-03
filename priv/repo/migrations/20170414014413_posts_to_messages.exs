# Couples more closely to the facebook API
# developers.facebook.com/docs/messenger-platform/webhook-reference/message
import Ecto.Query

defmodule Pesterbot.Repo.Migrations.PostsToMessages do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :sender_id, :string
      add :recipient_id, :string
      add :timestamp, :integer
      add :message_id, :string
      add :message_seq, :integer
      add :message_text, :text
      add :quick_reply, :string
      add :json_message, :text
    end

    flush()

    "posts"
    |> update([p], set: [sender_id: p.uid])
    |> Pesterbot.Repo.update_all([])
    "posts"
    |> update([p], set: [message_text: p.data])
    |> Pesterbot.Repo.update_all([])
    # thanks to @Dogbert!
    # stackoverflow.com/questions/44743915/ecto-how-to-call-a-function-in-an-update
    "posts"
    |> update([p], set: [
      timestamp: fragment(
        "EXTRACT(EPOCH FROM ?::timestamp with time zone)",
        p.time
      )
    ])
    |> Pesterbot.Repo.update_all([])

    rename table(:posts), to: table(:messages)
    alter table(:messages) do
      remove :uid
      remove :time
      remove :data
    end
  end

  def down do
    alter table(:messages) do
      add :uid, :string
      add :time, :string
      add :data, :text
    end
    rename table(:messages), to: table(:posts)

    flush()

    "posts"
    |> update([p], set: [uid: p.sender_id])
    |> Pesterbot.Repo.update_all([])
    "posts"
    |> update([p], set: [data: p.message_text])
    |> Pesterbot.Repo.update_all([])
    "posts"
    |> update([p], set: [
      time: fragment(
        "to_char(to_timestamp(?), 'Dy Mon DD HH24:MI:SS TZ YYYY')",
        p.timestamp
      )
    ])
    |> Pesterbot.Repo.update_all([])

    alter table(:posts) do
      remove :sender_id
      remove :recipient_id
      remove :timestamp
      remove :message_id
      remove :message_seq
      remove :message_text
      remove :quick_reply
      remove :json_message
    end
  end

end
