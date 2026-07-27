defmodule Masthead.Workers.SuspendUnconfirmed do
  @moduledoc """
  Daily sweep (Oban cron) that suspends accounts which never confirmed their
  email within 30 days of signing up — taking offline any of their sites left
  without a verified member — and emails them how to restore access. Unlike a
  disable, a suspended user can still log in; the verify gate pins them to the
  confirm screen until they do. Confirming re-enables the account and its sites.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3
  use MastheadWeb, :verified_routes

  require Logger

  alias Masthead.Accounts
  alias Masthead.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    suspended = Accounts.suspend_unconfirmed_accounts()

    Enum.each(suspended, fn user ->
      Accounts.notify_once(user.id, "suspended", fn ->
        UserNotifier.deliver_account_suspended(user, url(~p"/login"))
      end)
    end)

    case length(suspended) do
      0 -> :ok
      n -> Logger.info("SuspendUnconfirmed: suspended #{n} unconfirmed account(s)")
    end

    :ok
  end
end
