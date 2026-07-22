defmodule Masthead.Workers.OnboardingReminder do
  @moduledoc """
  Daily cron sweep: for each site with reminder-eligible actions still open a
  week after they were created, send every eligible member a single reminder
  email and mark those actions reminded (so it never repeats). Actions are
  grouped by site so a member gets one email per site, however many actions are
  due. A member is eligible when their account is confirmed, active, and opted
  in to onboarding emails; sites with no eligible member are left for a later
  sweep (so a member who confirms later still gets nudged).
  """
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Masthead.Actions
  alias Masthead.Accounts.User
  alias Masthead.Accounts.UserNotifier
  alias MastheadWeb.OnboardingToken

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    emails =
      Actions.due_reminders()
      |> Enum.group_by(& &1.site_id)
      |> Enum.map(fn {_site_id, actions} -> remind_site(actions) end)
      |> Enum.sum()

    if emails > 0, do: Logger.info("OnboardingReminder: sent #{emails} reminder email(s)")
    :ok
  end

  defp remind_site(actions) do
    site = hd(actions).site
    recipients = Enum.filter(site.members, &eligible?/1)

    if recipients == [] do
      # No one to email yet — leave the actions un-reminded for a later sweep.
      0
    else
      items =
        Enum.map(actions, fn action ->
          %{
            title: Actions.title(action),
            message: action.message,
            cta: Actions.cta(action),
            url: action_url(action)
          }
        end)

      Enum.each(recipients, fn member ->
        UserNotifier.deliver_onboarding_reminder(
          member.email,
          site.name,
          items,
          OnboardingToken.unsubscribe_url(member.id)
        )
      end)

      Enum.each(actions, &Actions.mark_reminded/1)
      length(recipients)
    end
  end

  defp eligible?(%User{} = user) do
    User.confirmed?(user) and not User.disabled?(user) and user.wants_onboarding_emails
  end

  defp action_url(%{path: nil}), do: MastheadWeb.Endpoint.url()
  defp action_url(%{path: path}), do: MastheadWeb.Endpoint.url() <> path
end
