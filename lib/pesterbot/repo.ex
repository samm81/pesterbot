defmodule Pesterbot.Repo do
  @moduledoc """
  The ecto repo for the pesterbot PostgreSQL database
  """

  use Ecto.Repo,
    otp_app: :pesterbot
end
