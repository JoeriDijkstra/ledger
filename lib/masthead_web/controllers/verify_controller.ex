defmodule MastheadWeb.VerifyController do
  use MastheadWeb, :controller

  # The forced-verify screen a suspended (day-30 unconfirmed) account is pinned
  # to by `UserAuth.require_verified_user/2`. Confirming (via the emailed
  # `/confirm/:token` link, which the resend button re-sends) lifts the
  # suspension and reactivates the account and its sites.
  def show(conn, _params) do
    render(conn, :show, email: conn.assigns.current_user.email)
  end
end
