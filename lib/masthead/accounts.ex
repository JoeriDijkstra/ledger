defmodule Masthead.Accounts do
  import Ecto.Query

  alias Masthead.Repo
  alias Masthead.Accounts.User
  alias Masthead.Accounts.UserToken
  alias Masthead.Accounts.UserNotifier
  alias Masthead.Accounts.UserIdentity
  alias Masthead.Sites

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  @doc """
  Registers a user who accepted a site invitation. The account starts
  confirmed (the invite email proved control of the address).
  """
  def register_invited_user(attrs) do
    %User{}
    |> User.invited_registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Email tokens

  @doc """
  Builds a token for `user` in `context`, persists its hash, and returns
  the raw token to embed in an email link.
  """
  def generate_email_token(%User{} = user, context) do
    {raw_token, user_token} = UserToken.build_email_token(user, context)
    Repo.insert!(user_token)
    raw_token
  end

  @doc """
  Resolves a raw token to its user if the token is valid, the right
  context, and not expired. Returns `nil` otherwise.
  """
  def get_user_by_token(raw_token, context)
      when is_binary(raw_token) and is_binary(context) do
    case UserToken.verify_email_token_query(raw_token, context) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_token(_, _), do: nil

  @doc """
  Deletes `user`'s tokens. `contexts` is a list of context strings or
  `:all`. Used to make tokens single-use and to revoke on disable.
  """
  def delete_user_tokens(%User{} = user, contexts) do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, contexts))
  end

  ## Email confirmation

  @doc """
  Sends a confirmation link. `url_fun` turns a raw token into the full
  confirmation URL. No-op (`{:error, :already_confirmed}`) if the email
  is already confirmed.
  """
  def deliver_user_confirmation_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    if User.confirmed?(user) do
      {:error, :already_confirmed}
    else
      token = generate_email_token(user, "confirm")
      UserNotifier.deliver_confirmation_instructions(user, url_fun.(token))
    end
  end

  @doc """
  Confirms the account behind `token`. Marks the email confirmed and
  burns every outstanding confirm token (single-use). `:error` if the
  token is invalid or expired.
  """
  def confirm_user(token) when is_binary(token) do
    with %User{} = user <- get_user_by_token(token, "confirm"),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"])
    )
  end

  ## Password reset

  @doc "Changeset for the set-new-password form."
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  @doc """
  Sends a reset link. `url_fun` turns a raw token into the full URL.
  Callers must keep this enumeration-safe (don't reveal whether the
  address exists).
  """
  def deliver_user_reset_password_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    token = generate_email_token(user, "reset_password")
    UserNotifier.deliver_reset_password_instructions(user, url_fun.(token))
  end

  @doc "User behind a valid, unexpired reset token, or nil."
  def get_user_by_reset_password_token(token) when is_binary(token) do
    get_user_by_token(token, "reset_password")
  end

  @doc """
  Sets a new password. Reaching here proves control of the email, so we
  also confirm the account (if not already) and revoke every token so
  outstanding reset/confirm links die.
  """
  def reset_user_password(%User{} = user, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> maybe_confirm()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  defp maybe_confirm(changeset) do
    case changeset.data do
      %User{confirmed_at: nil} ->
        Ecto.Changeset.put_change(
          changeset,
          :confirmed_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      _ ->
        changeset
    end
  end

  ## Password change (signed-in)

  @doc """
  Changes the password of a signed-in user, requiring the current
  password. `{:error, :invalid_current_password}` if it doesn't match.
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(attrs)
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  ## Account disable / enable

  @doc """
  Soft-disables `user`: stamps `disabled_at`, cascades to every site the
  user owns (those sites stop resolving — 404), and revokes all tokens.
  Idempotent. Re-enable via `enable_user/1`.
  """
  def disable_user(%User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.disable_changeset(user))
    |> Ecto.Multi.run(:sites, fn _repo, _ ->
      {:ok, Sites.disable_sites_for_user(user.id)}
    end)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Opts the user out of onboarding/nudge emails (one-click unsubscribe).
  Idempotent; returns `:ok` whether or not the user exists.
  """
  def unsubscribe_onboarding_emails(user_id) do
    case Repo.get(User, user_id) do
      nil -> :ok
      user -> user |> User.onboarding_emails_changeset(false) |> Repo.update() && :ok
    end
  end

  @doc """
  Disables accounts that never confirmed their email within
  `older_than_days` (default 7) of signing up. Skips already-disabled
  accounts. Returns the number disabled. Driven by
  `Masthead.Workers.DisableUnconfirmed` on a daily cron.
  """
  def disable_unconfirmed_accounts(older_than_days \\ 7) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-older_than_days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    stale =
      Repo.all(
        from u in User,
          where:
            is_nil(u.confirmed_at) and is_nil(u.disabled_at) and
              u.inserted_at < ^cutoff
      )

    Enum.each(stale, &disable_user/1)
    length(stale)
  end

  ## OAuth / SSO

  @doc """
  Resolves an OAuth login to a user. `info` is
  `%{provider, uid, email, email_verified}`.

    * known identity → that user
    * else, a verified email matching an existing account → link a new
      identity to it (account takeover is prevented by requiring the
      provider to vouch the email is verified)
    * else → create a fresh, already-confirmed account + identity

  Returns `{:ok, user}` or `{:error, :disabled | :no_email |
  :email_unverified}`.
  """
  def get_or_create_user_from_oauth(%{provider: provider, uid: uid} = info) do
    provider = to_string(provider)
    uid = to_string(uid)

    case Repo.get_by(UserIdentity, provider: provider, provider_uid: uid) do
      %UserIdentity{} = identity ->
        return_if_active(Repo.preload(identity, :user).user)

      nil ->
        link_or_create(provider, uid, info)
    end
  end

  defp link_or_create(provider, uid, %{email: email} = info)
       when is_binary(email) and email != "" do
    case get_user_by_email(email) do
      %User{} = user ->
        cond do
          User.disabled?(user) -> {:error, :disabled}
          not Map.get(info, :email_verified, false) -> {:error, :email_unverified}
          true -> link_identity(user, provider, uid)
        end

      nil ->
        create_user_with_identity(email, provider, uid)
    end
  end

  defp link_or_create(_provider, _uid, _info), do: {:error, :no_email}

  defp link_identity(user, provider, uid) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{user_id: user.id, provider: provider, provider_uid: uid})
    |> Repo.insert(on_conflict: :nothing)

    {:ok, user}
  end

  defp create_user_with_identity(email, provider, uid) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.oauth_registration_changeset(%User{}, %{email: email}))
    |> Ecto.Multi.insert(:identity, fn %{user: user} ->
      UserIdentity.changeset(%UserIdentity{}, %{
        user_id: user.id,
        provider: provider,
        provider_uid: uid
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp return_if_active(%User{} = user) do
    if User.disabled?(user), do: {:error, :disabled}, else: {:ok, user}
  end

  @doc """
  Re-enables a disabled account and restores its sites. Intended for
  console / admin use (there is no self-service re-enable).
  """
  def enable_user(%User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.enable_changeset(user))
    |> Ecto.Multi.run(:sites, fn _repo, _ ->
      {:ok, Sites.enable_sites_for_user(user.id)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  # ---- admin ----

  @doc """
  Users for the admin overview, newest first, with optional filter +
  search. Capped at `count` rows — narrow with the filter + search rather
  than paging.
  """
  def list_all_users(filter \\ :all, search_query \\ nil, count \\ 20) do
    from(u in User, order_by: [desc: u.inserted_at])
    |> apply_filter(filter)
    |> apply_search(search_query)
    |> limit(^count)
    |> Repo.all()
  end

  defp apply_filter(query, filter) do
    case filter do
      :verified -> from u in query, where: not is_nil(u.confirmed_at)
      :unverified -> from u in query, where: is_nil(u.confirmed_at)
      :disabled -> from u in query, where: not is_nil(u.disabled_at)
      :admins -> from u in query, where: u.admin == true
      _ -> query
    end
  end

  defp apply_search(query, search_query) do
    if search_query && search_query != "" do
      from u in query, where: ilike(u.email, ^"%#{search_query}%")
    else
      query
    end
  end

  @doc "Stamps the user's last successful login. Called from `UserAuth.log_in_user/3`."
  def record_login(%User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    user |> Ecto.Changeset.change(last_login_at: now) |> Repo.update()
  end

  @doc "Marks a user's email confirmed without a token (admin verify)."
  def verify_user(%User{} = user), do: user |> User.confirm_changeset() |> Repo.update()

  @doc "Grants or revokes platform-admin access (console / admin use)."
  def set_admin(%User{} = user, admin?) when is_boolean(admin?) do
    user |> User.admin_changeset(admin?) |> Repo.update()
  end
end
