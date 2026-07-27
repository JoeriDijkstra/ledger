defmodule Masthead.Accounts.UserToken do
  @moduledoc """
  Single-use, hashed tokens for account email flows.

  The raw token is random 32 bytes, URL-safe-Base64 encoded, and only
  ever appears in the email link. What's stored is its SHA-256 hash, so
  a leaked database row can't be replayed as a valid link.

  Contexts and validity windows:
    * `"confirm"`        — 30 days (matches the unconfirmed-account window)
    * `"reset_password"` — 1 day
  """
  use Ecto.Schema

  import Ecto.Query

  alias Masthead.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  @confirm_validity_days 30
  @reset_password_validity_days 1

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Masthead.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a token tied to `user` for `context`. Returns
  `{raw_token, %UserToken{}}` — email the raw token, persist the struct.
  """
  def build_email_token(user, context)
      when context in ["confirm", "reset_password"] do
    raw = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, raw)

    {Base.url_encode64(raw, padding: false),
     %UserToken{
       token: hashed,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Query returning the user for a still-valid raw token in `context`,
  or no rows if the token is unknown, wrong-context, or expired.
  """
  def verify_email_token_query(raw_token, context) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        days = validity_days(context)

        query =
          from token in by_token_and_context_query(hashed, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "All tokens for `user` in any of `contexts` (for invalidation)."
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, contexts) when is_list(contexts) do
    from t in UserToken,
      where: t.user_id == ^user.id and t.context in ^contexts
  end

  defp by_token_and_context_query(hashed_token, context) do
    from UserToken, where: [token: ^hashed_token, context: ^context]
  end

  defp validity_days("confirm"), do: @confirm_validity_days
  defp validity_days("reset_password"), do: @reset_password_validity_days
end
