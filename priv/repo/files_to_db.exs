for file <- File.ls!("users" ) do
  Pesterbot.Router.get_user!(file)
  |> Pesterbot.Repo.insert!

  File.read!("users/" <> file)
  |> String.split("\n", trim: true)
  |> Enum.map(
    fn (line) ->
      [time, data] = String.split(line, "      ")
      Pesterbot.Repo.insert!(%Pesterbot.Post{ uid: file, time: time, data: data })
    end
  )
end
