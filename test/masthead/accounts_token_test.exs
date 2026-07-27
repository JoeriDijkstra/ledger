defmodule Masthead.AccountsTokenTest do
  use Masthead.DataCase

  import Ecto.Query

  alias Masthead.Accounts
  alias Masthead.Accounts.UserToken
  alias Masthead.Repo

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "tok-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  defp backdate_tokens(user, seconds_ago) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-seconds_ago, :second)
      |> DateTime.truncate(:second)

    {n, _} =
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: at]
      )

    n
  end

  test "generate_email_token stores only the hash, not the raw token", %{user: user} do
    raw = Accounts.generate_email_token(user, "confirm")

    stored = Repo.one(from t in UserToken, where: t.user_id == ^user.id)
    assert stored.context == "confirm"
    assert stored.sent_to == user.email
    refute stored.token == raw
    assert stored.token == :crypto.hash(:sha256, Base.url_decode64!(raw, padding: false))
  end

  test "a fresh token resolves to its user in the right context", %{user: user} do
    raw = Accounts.generate_email_token(user, "confirm")

    assert %{id: id} = Accounts.get_user_by_token(raw, "confirm")
    assert id == user.id
  end

  test "a token does not resolve under a different context", %{user: user} do
    raw = Accounts.generate_email_token(user, "confirm")

    refute Accounts.get_user_by_token(raw, "reset_password")
  end

  test "garbage / malformed tokens return nil", %{user: _user} do
    refute Accounts.get_user_by_token("not-base64-$$$", "confirm")
    refute Accounts.get_user_by_token("", "confirm")
  end

  test "a confirm token expires after 30 days", %{user: user} do
    raw = Accounts.generate_email_token(user, "confirm")

    backdate_tokens(user, 30 * 24 * 60 * 60 - 60)
    assert Accounts.get_user_by_token(raw, "confirm")

    backdate_tokens(user, 30 * 24 * 60 * 60 + 60)
    refute Accounts.get_user_by_token(raw, "confirm")
  end

  test "a reset_password token expires after 1 day", %{user: user} do
    raw = Accounts.generate_email_token(user, "reset_password")

    backdate_tokens(user, 24 * 60 * 60 - 60)
    assert Accounts.get_user_by_token(raw, "reset_password")

    backdate_tokens(user, 24 * 60 * 60 + 60)
    refute Accounts.get_user_by_token(raw, "reset_password")
  end

  test "delete_user_tokens revokes by context", %{user: user} do
    confirm = Accounts.generate_email_token(user, "confirm")
    reset = Accounts.generate_email_token(user, "reset_password")

    Accounts.delete_user_tokens(user, ["confirm"])

    refute Accounts.get_user_by_token(confirm, "confirm")
    assert Accounts.get_user_by_token(reset, "reset_password")

    Accounts.delete_user_tokens(user, :all)
    refute Accounts.get_user_by_token(reset, "reset_password")
  end
end
