defmodule Masthead.SuspendUnconfirmedTest do
  use Masthead.DataCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.{Accounts, Sites}
  alias Masthead.Accounts.User
  alias Masthead.Workers.{Email, SuspendUnconfirmed}

  setup do
    Masthead.Themes.Seed.run()
    :ok
  end

  defp user(prefix) do
    {:ok, u} =
      Accounts.register_user(%{
        "email" => "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    u
  end

  defp backdate(user, days) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [inserted_at: at])
    user
  end

  test "suspends only unconfirmed accounts older than 30 days" do
    stale = user("stale") |> backdate(31)
    fresh = user("fresh") |> backdate(10)

    confirmed_old = user("conf")
    {:ok, _} = Accounts.confirm_user(Accounts.generate_email_token(confirmed_old, "confirm"))
    backdate(confirmed_old, 60)

    assert [%User{}] = suspended = Accounts.suspend_unconfirmed_accounts()
    assert hd(suspended).id == stale.id

    stale = Repo.reload(stale)
    # Suspended, not disabled — the account can still log in to confirm.
    assert User.suspended?(stale)
    refute User.disabled?(stale)

    refute User.suspended?(Repo.reload(fresh))
    refute User.suspended?(Repo.reload(confirmed_old))
  end

  test "suspension takes the user's orphaned site offline; confirming restores it" do
    owner = user("owner") |> backdate(31)

    {:ok, site} =
      Sites.create_site(
        %{"slug" => "sus#{System.unique_integer([:positive])}", "name" => "S"},
        owner
      )

    Accounts.suspend_unconfirmed_accounts()
    refute Sites.get_site_by_slug(site.slug)

    # Tokens are NOT revoked by suspension, so the confirm link still works.
    {:ok, restored} = Accounts.confirm_user(Accounts.generate_email_token(owner, "confirm"))
    refute User.suspended?(restored)
    assert Sites.get_site_by_slug(site.slug)
  end

  test "is idempotent — an already-suspended account isn't swept again" do
    user("stale") |> backdate(40)

    assert [_] = Accounts.suspend_unconfirmed_accounts()
    assert [] = Accounts.suspend_unconfirmed_accounts()
  end

  test "the Oban worker suspends and emails exactly once" do
    stale = user("stale") |> backdate(35)

    assert :ok = perform_job(SuspendUnconfirmed, %{})
    assert User.suspended?(Repo.reload(stale))

    assert_enqueued(
      worker: Email,
      args: %{to: stale.email, subject: "Your Masthead account has been suspended"}
    )

    # A second run (account still unconfirmed but already suspended) sends nothing more.
    assert :ok = perform_job(SuspendUnconfirmed, %{})

    assert 1 ==
             Repo.aggregate(
               from(j in Oban.Job, where: fragment("? ->> 'to' = ?", j.args, ^stale.email)),
               :count
             )
  end
end
