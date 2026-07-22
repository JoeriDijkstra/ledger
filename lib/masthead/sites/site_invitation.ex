defmodule Masthead.Sites.SiteInvitation do
  @moduledoc """
  Pending invitation for an email address that has **no account yet**. Once
  the invitee signs up via the emailed link the invitation is consumed and a
  membership is created. Invitees who already have an account are added
  immediately and never get an invitation row.

  Like `Masthead.Accounts.UserToken`, the raw token only ever appears in the
  email link; the stored `token` is its SHA-256 hash, so a leaked row can't be
  replayed. Invitations are valid for 7 days.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Masthead.Sites.SiteInvitation

  @hash_algorithm :sha256
  @rand_size 32
  @validity_days 7

  schema "site_invitations" do
    field :email, :string
    field :token, :binary
    belongs_to :site, Masthead.Sites.Site

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an invitation for `email` to join `site`. Returns
  `{raw_token, %SiteInvitation{}}` — email the raw token, persist the struct.
  """
  def build(site_id, email) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, raw)

    {Base.url_encode64(raw, padding: false),
     %SiteInvitation{
       token: hashed,
       email: normalize_email(email),
       site_id: site_id
     }}
  end

  @doc """
  Query returning the invitation (with its site) for a still-valid raw token,
  or no rows if the token is unknown or expired.
  """
  def verify_token_query(raw_token) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)

        query =
          from i in SiteInvitation,
            where: i.token == ^hashed and i.inserted_at > ago(@validity_days, "day"),
            preload: [:site]

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Lowercase + trim, matching how account emails are stored (citext)."
  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()
end
