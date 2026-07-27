defmodule Masthead.AccountsConfirmationTest do
  use Masthead.DataCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.Accounts
  alias Masthead.Accounts.User

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "conf-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  describe "deliver_user_confirmation_instructions/2" do
    test "enqueues a confirmation email and a confirm token", %{user: user} do
      assert {:ok, %{to: to}} =
               Accounts.deliver_user_confirmation_instructions(
                 user,
                 &"http://x/confirm/#{&1}"
               )

      assert to == user.email
      assert_enqueued(worker: Masthead.Workers.Email, args: %{"to" => user.email})

      assert Repo.exists?(
               from t in Masthead.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
             )
    end

    test "is a no-op once confirmed", %{user: user} do
      {:ok, user} = confirm(user)

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, &"http://x/#{&1}")
    end
  end

  describe "confirm_user/1" do
    test "confirms the account and burns the token (single-use)", %{user: user} do
      refute User.confirmed?(user)
      token = Accounts.generate_email_token(user, "confirm")

      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert User.confirmed?(confirmed)

      # token is single-use
      assert :error = Accounts.confirm_user(token)
    end

    test "rejects an invalid token", %{user: _user} do
      assert :error = Accounts.confirm_user("bogus")
    end

    test "rejects an expired token", %{user: user} do
      token = Accounts.generate_email_token(user, "confirm")
      backdate_confirm_tokens(user, 31 * 24 * 60 * 60)
      assert :error = Accounts.confirm_user(token)
    end
  end

  defp confirm(user) do
    token = Accounts.generate_email_token(user, "confirm")
    Accounts.confirm_user(token)
  end

  defp backdate_confirm_tokens(user, seconds_ago) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-seconds_ago, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(t in Masthead.Accounts.UserToken,
        where: t.user_id == ^user.id and t.context == "confirm"
      ),
      set: [inserted_at: at]
    )
  end
end
