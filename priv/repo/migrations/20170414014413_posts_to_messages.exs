# Couples more closely to the facebook API
# https://developers.facebook.com/docs/messenger-platform/webhook-reference/message
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

    from(p in "posts",
      update: [set: [ sender_id: p.uid ]])
    |> Pesterbot.Repo.update_all([])
    from(p in "posts",
      update: [set: [ message_text: p.data ]])
    |> Pesterbot.Repo.update_all([])
    # thanks to @Dogbert! https://stackoverflow.com/questions/44743915/ecto-how-to-call-a-function-in-an-update
    from(p in "posts",
      update: [set: [timestamp: fragment("EXTRACT(EPOCH FROM ?::timestamp with time zone)", p.time)]])
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

    from(p in "posts",
      update: [set: [ uid: p.sender_id ]])
    |> Pesterbot.Repo.update_all([])
    from(p in "posts",
      update: [set: [ data: p.message_text ]])
    |> Pesterbot.Repo.update_all([])
    from(p in "posts",
      update: [set: [time: fragment("to_char(to_timestamp(?), 'Dy Mon DD HH24:MI:SS TZ YYYY')", p.timestamp)]])
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
