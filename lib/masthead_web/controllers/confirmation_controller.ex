defmodule MastheadWeb.ConfirmationController do
  use MastheadWeb, :controller

  alias Masthead.Accounts
  alias Masthead.Accounts.User

  # GET /confirm/:token — the link from the email. Works logged-in or out.
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        Accounts.deliver_welcome(user, url(~p"/sites"))

        conn
        |> put_flash(:info, "Thanks — your email is confirmed.")
        |> redirect(to: post_confirm_path(conn))

      :error ->
        conn
        |> put_flash(
          :error,
          "That confirmation link is invalid or has expired. Request a new one below."
        )
        |> redirect(to: post_confirm_path(conn))
    end
  end

  # POST /confirm — "resend" from the unconfirmed banner. Enumeration-safe:
  # always the same response whether or not a mail actually went out.
  def create(conn, _params) do
    case conn.assigns[:current_user] do
      %User{} = user ->
        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/confirm/#{&1}")
        )

      _ ->
        :noop
    end

    conn
    |> put_flash(:info, "If your email isn't confirmed yet, a new link is on its way.")
    |> redirect(to: resend_path(conn))
  end

  # After a confirm attempt: logged-in users go to their sites, else the login
  # page. (A user who just confirmed is no longer suspended, so `/sites` loads.)
  defp post_confirm_path(conn) do
    if conn.assigns[:current_user], do: ~p"/sites", else: ~p"/login"
  end

  # After a resend, keep a still-suspended user on the verify screen so the
  # "new link is on its way" flash is shown rather than lost to a bounce.
  defp resend_path(conn) do
    case conn.assigns[:current_user] do
      %User{suspended_at: at} when not is_nil(at) -> ~p"/verify"
      _ -> post_confirm_path(conn)
    end
  end
end
