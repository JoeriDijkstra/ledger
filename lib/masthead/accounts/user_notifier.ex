defmodule Masthead.Accounts.UserNotifier do
  @moduledoc """
  Builds account emails and enqueues them via `Masthead.Workers.Email`
  (Oban) so delivery survives a transient provider failure.

  Each email ships a branded HTML body (see `layout/2`) plus a plain-text
  fallback for deliverability. Callers pass fully-built URLs; this module
  does not know routes.
  """
  alias Masthead.Workers.Email

  @accent "#2563eb"
  @ink "#18181b"
  @body_fg "#3f3f46"
  @muted "#71717a"
  @rule "#e4e4e7"
  @page_bg "#f4f4f5"
  @font "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

  @doc "Email confirmation link for a new (or unconfirmed) account."
  def deliver_confirmation_instructions(user, url) do
    text = """
    Hi,

    Welcome to Masthead. Confirm your account by visiting the link below:

    #{url}

    This link expires in 30 days. If you didn't create a Masthead account, you
    can safely ignore this email.
    """

    html =
      layout([
        paragraph("Welcome to Masthead! Confirm your email address to activate your account."),
        button("Confirm your account", url),
        muted(
          "This link expires in 30 days. If you didn't create a Masthead account, you can safely ignore this email."
        )
      ])

    deliver(user.email, "Confirm your Masthead account", text, html)
  end

  @doc "One-time welcome, sent once an account is verified (or created via OAuth/invite)."
  def deliver_welcome(user, sites_url) do
    text = """
    Hi,

    Welcome to Masthead — your account is all set. Masthead gives you a simple
    website without the complexity: write in Markdown or HTML, pick a theme, and
    publish on your own subdomain.

    Jump in and create your first site:

    #{sites_url}
    """

    html =
      layout([
        paragraph("Welcome to Masthead — your account is all set."),
        paragraph(
          "Masthead gives you a simple website without the complexity: write in " <>
            "Markdown or HTML, pick a theme, and publish on your own subdomain."
        ),
        button("Go to your sites", sites_url)
      ])

    deliver(user.email, "Welcome to Masthead", text, html)
  end

  @doc "Day-14 nudge for an account that hasn't signed in for over a week."
  def deliver_login_reminder(user, login_url) do
    text = """
    Hi,

    We haven't seen you in a while. Your Masthead account is still here whenever
    you're ready to pick things back up — log in to keep building your site:

    #{login_url}
    """

    html =
      layout([
        paragraph("We haven't seen you in a while."),
        paragraph(
          "Your Masthead account is still here whenever you're ready to pick things " <>
            "back up. Log in to keep building your site."
        ),
        button("Log in", login_url)
      ])

    deliver(user.email, "Your Masthead account is waiting", text, html)
  end

  @doc """
  Verify-or-lose-it warning for an unconfirmed account. `days_left` is how long
  until the account is suspended (14 at day 16, 7 at day 23).
  """
  def deliver_verify_warning(user, confirm_url, days_left) do
    when_str = if days_left == 1, do: "1 day", else: "#{days_left} days"

    text = """
    Hi,

    Your Masthead email address still isn't confirmed. If it isn't confirmed
    within #{when_str}, your account will be suspended and any site with no other
    confirmed member will go offline.

    Confirm now to keep everything active:

    #{confirm_url}
    """

    html =
      layout([
        paragraph("Your Masthead email address still isn't confirmed."),
        paragraph(
          "If it isn't confirmed within #{when_str}, your account will be suspended and " <>
            "any site with no other confirmed member will go offline."
        ),
        button("Confirm your account", confirm_url),
        muted("Already confirmed? You can ignore this email.")
      ])

    deliver(user.email, "Confirm your email to keep your account active", text, html)
  end

  @doc "Day-30 notice that the (still-unconfirmed) account has been suspended, with recovery steps."
  def deliver_account_suspended(user, login_url) do
    text = """
    Hi,

    Your Masthead account has been suspended because your email address was never
    confirmed. Any site that had no other confirmed member is now offline.

    You can restore everything in two steps:

    1. Log in at #{login_url}
    2. Confirm your email from the prompt shown there

    As soon as you confirm, your account and its sites are reactivated
    automatically.
    """

    html =
      layout([
        paragraph(
          "Your Masthead account has been suspended because your email address was " <>
            "never confirmed. Any site that had no other confirmed member is now offline."
        ),
        paragraph("You can restore everything in two steps:"),
        paragraph("1. Log in below.  2. Confirm your email from the prompt shown there."),
        button("Log in to restore your account", login_url),
        muted("As soon as you confirm, your account and its sites are reactivated automatically.")
      ])

    deliver(user.email, "Your Masthead account has been suspended", text, html)
  end

  @doc "Password-reset link."
  def deliver_reset_password_instructions(user, url) do
    text = """
    Hi,

    You (or someone) requested a password reset for your Masthead account.
    Choose a new password by visiting the link below:

    #{url}

    This link expires in 1 day. If you didn't request this, ignore this
    email — your password will not change.
    """

    html =
      layout([
        paragraph("You (or someone) requested a password reset for your Masthead account."),
        button("Reset your password", url),
        muted(
          "This link expires in 1 day. If you didn't request this, you can ignore this email — your password won't change."
        )
      ])

    deliver(user.email, "Reset your Masthead password", text, html)
  end

  @doc """
  One reminder email for a single site's still-open onboarding actions.
  `items` is a list of `%{title:, message:, cta:, url:}` maps (grouped per
  site so the owner only ever gets one email), plus an `unsubscribe_url`.
  """
  def deliver_onboarding_reminder(to, site_name, items, unsubscribe_url) do
    lead =
      if length(items) == 1,
        do: "the following item requires is still open:",
        else: "the following items are still open:"

    text_list =
      Enum.map_join(items, "\n\n", fn %{title: t, message: m, url: u} ->
        "* #{t}\n  #{m}\n  #{u}"
      end)

    text = """
    Hi,

    #{site_name} requires your attention. #{lead}

    #{text_list}

    —
    Don't want these onboarding nudges? Unsubscribe here:
    #{unsubscribe_url}
    """

    html =
      layout(
        [
          paragraph("#{site_name} requires your attention, #{lead}"),
          Enum.map(items, &action_block/1)
        ],
        footer:
          ~s(Don't want these nudges? <a href="#{unsubscribe_url}" style="color:#{@muted};">Unsubscribe</a>.)
      )

    deliver(to, "#{site_name} requires your attention", text, html)
  end

  @doc "Notifies an existing user that they've been added to a site."
  def deliver_site_added_notification(user, site, site_url) do
    text = """
    Hi,

    You've been added to the site "#{site.name}" on Masthead. You can now
    collaborate on it. Open it here:

    #{site_url}
    """

    html =
      layout([
        paragraph(~s(You've been added to the site "#{site.name}" on Masthead.)),
        paragraph("You can now collaborate on it."),
        button("Open #{site.name}", site_url)
      ])

    deliver(user.email, ~s(You've been added to "#{site.name}"), text, html)
  end

  @doc """
  Invites an address with no account yet to collaborate on a site. `url` is
  the `/invite/:token` signup link.
  """
  def deliver_site_invitation(email, site, url) do
    text = """
    Hi,

    You've been invited to collaborate on the site "#{site.name}" on Masthead.
    Create your account to join:

    #{url}

    This link expires in 7 days. If you weren't expecting this invitation, you
    can safely ignore this email.
    """

    html =
      layout([
        paragraph(~s(You've been invited to collaborate on the site "#{site.name}" on Masthead.)),
        button("Accept invitation", url),
        muted(
          "This link expires in 7 days. If you weren't expecting this invitation, you can safely ignore this email."
        )
      ])

    deliver(email, ~s(You're invited to collaborate on "#{site.name}"), text, html)
  end

  # ---- delivery ----

  # Enqueue rather than send inline so a flaky provider retries.
  defp deliver(to, subject, text_body, html_body) do
    %{to: to, subject: subject, text_body: text_body, html_body: html_body}
    |> Email.new()
    |> Oban.insert()

    {:ok, %{to: to, subject: subject}}
  end

  # ---- HTML building blocks (inline styles only — email clients ignore <style>) ----

  defp layout(inner, opts \\ []) do
    footer = Keyword.get(opts, :footer)
    inner_html = inner |> List.flatten() |> Enum.join("\n")

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body style="margin:0;padding:0;background:#{@page_bg};font-family:#{@font};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@page_bg};">
          <tr>
            <td align="center" style="padding:32px 16px;">
              <table role="presentation" width="600" cellpadding="0" cellspacing="0"
                style="width:100%;max-width:600px;background:#ffffff;border:1px solid #{@rule};border-radius:12px;">
                <tr>
                  <td style="padding:24px 28px 0;font-family:#{@font};">
                    <span style="color:#{@accent};font-size:18px;vertical-align:middle;">&#9679;</span>
                    <span style="color:#{@ink};font-weight:700;font-size:18px;vertical-align:middle;">Masthead</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:20px 28px 28px;font-family:#{@font};">
                    #{inner_html}
                  </td>
                </tr>
                <tr>
                  <td style="padding:18px 28px;border-top:1px solid #{@rule};color:#a1a1aa;font-size:12px;line-height:1.6;font-family:#{@font};">
                    #{if footer, do: footer <> "<br />", else: ""}Masthead — simple websites without the complexity.
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp paragraph(text) do
    ~s(<p style="color:#{@body_fg};font-size:15px;line-height:1.6;margin:0 0 16px;">#{esc(text)}</p>)
  end

  defp muted(text) do
    ~s(<p style="color:#{@muted};font-size:13px;line-height:1.5;margin:16px 0 0;">#{esc(text)}</p>)
  end

  defp button(label, url) do
    ~s(<p style="margin:0 0 4px;"><a href="#{url}" style="display:inline-block;background:#{@accent};color:#ffffff;text-decoration:none;font-weight:600;font-size:15px;padding:11px 22px;border-radius:8px;">#{esc(label)}</a></p>)
  end

  defp action_block(%{title: title, message: message, url: url} = item) do
    cta = Map.get(item, :cta) || "Open"

    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 16px;">
      <tr>
        <td style="padding:16px 18px;background:#{@page_bg};border-radius:10px;font-family:#{@font};">
          <div style="color:#{@ink};font-weight:600;font-size:15px;margin:0 0 4px;">#{esc(title)}</div>
          <div style="color:#{@muted};font-size:14px;line-height:1.5;margin:0 0 12px;">#{esc(message)}</div>
          #{button(cta, url)}
        </td>
      </tr>
    </table>
    """
  end

  defp esc(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
