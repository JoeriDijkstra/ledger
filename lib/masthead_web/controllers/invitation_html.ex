defmodule MastheadWeb.InvitationHTML do
  use MastheadWeb, :html

  def new(assigns) do
    ~H"""
    <div class="auth-page">
      <div class="auth-card">
        <h1>Join {@invitation.site.name}</h1>
        <p class="meta">
          You've been invited to collaborate. Create your account to get started.
        </p>

        <form action={~p"/invite/#{@token}"} method="post" data-confirm-password>
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <.error_list changeset={@changeset} />
          <label>
            Email <input type="email" name="user[email]" value={@invitation.email} readonly />
          </label>
          <label>
            Password (min 8 chars)
            <input type="password" name="user[password]" required minlength="8" autofocus />
          </label>
          <label>
            Confirm password
            <input type="password" name="user[password_confirmation]" required minlength="8" />
          </label>
          <button type="submit">Create account &amp; join</button>
        </form>

        <p class="meta">
          Already have an account? <a href={~p"/login"}>Sign in</a>
        </p>
      </div>
    </div>
    """
  end

  attr :changeset, :map, required: true

  defp error_list(assigns) do
    ~H"""
    <ul :if={@changeset.action && @changeset.errors != []} class="errors">
      <li :for={{field, {msg, _}} <- @changeset.errors}>{field}: {msg}</li>
    </ul>
    """
  end
end
