defmodule Masthead.Workers.LifecycleEmailsTest do
  use Masthead.DataCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.Accounts
  alias Masthead.Accounts.User
  alias Masthead.Workers.LifecycleEmails

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

  defp set(user, fields) do
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: fields)
    Repo.reload(user)
  end

  defp days_ago(days),
    do:
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

  defp enqueued_to?(email, subject) do
    Repo.exists?(
      from j in Oban.Job,
        where:
          j.worker == "Masthead.Workers.Email" and
            fragment("? ->> 'to' = ?", j.args, ^email) and
            fragment("? ->> 'subject' = ?", j.args, ^subject)
    )
  end

  test "day-16 sends the 'will be disabled' warning to unconfirmed accounts" do
    u = user("d16") |> set(inserted_at: days_ago(17))

    assert :ok = perform_job(LifecycleEmails, %{})
    assert enqueued_to?(u.email, "Confirm your email to keep your account active")
  end

  test "day-23 also warns, and day-30+ is left to the suspend sweep" do
    d23 = user("d23") |> set(inserted_at: days_ago(24))
    d31 = user("d31") |> set(inserted_at: days_ago(31))

    assert :ok = perform_job(LifecycleEmails, %{})

    assert enqueued_to?(d23.email, "Confirm your email to keep your account active")
    # Past the 30-day window -> not warned here (SuspendUnconfirmed handles it).
    refute enqueued_to?(d31.email, "Confirm your email to keep your account active")
  end

  test "day-14 nudges an inactive account regardless of verification, once" do
    inactive =
      user("d14")
      |> set(inserted_at: days_ago(15), last_login_at: days_ago(9), confirmed_at: days_ago(15))

    assert :ok = perform_job(LifecycleEmails, %{})
    assert enqueued_to?(inactive.email, "Your Masthead account is waiting")

    # Re-running the sweep doesn't send a second nudge.
    assert :ok = perform_job(LifecycleEmails, %{})

    count =
      Repo.aggregate(
        from(j in Oban.Job,
          where:
            fragment("? ->> 'to' = ?", j.args, ^inactive.email) and
              fragment("? ->> 'subject' = ?", j.args, "Your Masthead account is waiting")
        ),
        :count
      )

    assert count == 1
  end

  test "day-14 skips a recently-active user and one who opted out" do
    active = user("act") |> set(inserted_at: days_ago(15), last_login_at: days_ago(2))

    opted_out =
      user("opt")
      |> set(
        inserted_at: days_ago(15),
        last_login_at: days_ago(10),
        wants_onboarding_emails: false
      )

    assert :ok = perform_job(LifecycleEmails, %{})

    refute enqueued_to?(active.email, "Your Masthead account is waiting")
    refute enqueued_to?(opted_out.email, "Your Masthead account is waiting")
  end

  test "confirmed accounts get no verify warning" do
    confirmed = user("ok") |> set(inserted_at: days_ago(20), confirmed_at: days_ago(20))

    assert :ok = perform_job(LifecycleEmails, %{})
    refute enqueued_to?(confirmed.email, "Confirm your email to keep your account active")
  end
end
