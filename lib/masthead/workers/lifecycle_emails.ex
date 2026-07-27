defmodule Masthead.Workers.LifecycleEmails do
  @moduledoc """
  Daily sweep (Oban cron) for the staged onboarding emails that aren't tied to a
  single event:

    * day 14 — a "we miss you" nudge to any active account that hasn't signed in
      for over a week (respects the onboarding-email opt-out);
    * day 16 — a warning that an unconfirmed account will be suspended in 14 days;
    * day 23 — the same warning with 7 days left.

  Each send is guarded by `Accounts.notify_once/3` so re-running the sweep on the
  same account never sends twice. The day-7 onboarding checklist reminder
  (`OnboardingReminder`) and the day-30 suspension (`SuspendUnconfirmed`) are
  separate workers.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 3
  use MastheadWeb, :verified_routes

  require Logger

  alias Masthead.Accounts
  alias Masthead.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    sent =
      login_reminders() +
        verify_warnings(16, 23, "verify_warning_16", 14) +
        verify_warnings(23, 30, "verify_warning_23", 7)

    if sent > 0, do: Logger.info("LifecycleEmails: sent #{sent} email(s)")
    :ok
  end

  defp login_reminders do
    Accounts.accounts_due_for_login_reminder()
    |> Enum.count(fn user ->
      :ok ==
        Accounts.notify_once(user.id, "login_reminder", fn ->
          UserNotifier.deliver_login_reminder(user, url(~p"/login"))
        end)
    end)
  end

  defp verify_warnings(min_days, max_days, kind, days_left) do
    Accounts.unconfirmed_accounts_aged(min_days, max_days)
    |> Enum.count(fn user ->
      :ok ==
        Accounts.notify_once(user.id, kind, fn ->
          token = Accounts.generate_email_token(user, "confirm")
          UserNotifier.deliver_verify_warning(user, url(~p"/confirm/#{token}"), days_left)
        end)
    end)
  end
end
