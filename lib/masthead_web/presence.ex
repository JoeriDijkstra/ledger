defmodule MastheadWeb.Presence do
  @moduledoc """
  Tracks which members are currently viewing a site's admin. Used by the
  shared `:load_site` hook to show a "who's viewing" cluster in the shell.
  """
  use Phoenix.Presence,
    otp_app: :masthead,
    pubsub_server: Masthead.PubSub
end
