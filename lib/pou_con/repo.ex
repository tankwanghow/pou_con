defmodule PouCon.Repo do
  use Ecto.Repo,
    otp_app: :pou_con,
    adapter: Ecto.Adapters.SQLite3
end
