defmodule MastheadWeb.VerifyControllerTest do
  use MastheadWeb.ConnCase
  use Oban.Testing, repo: Masthead.Repo

  import Ecto.Query

  alias Masthead.Accounts
  alias Masthead.Accounts.User
  alias Masthead.Repo

  defp user(opts) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "vg-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    fields =
      [
        confirmed_at: opts[:confirmed],
        suspended_at: opts[:suspended],
        disabled_at: opts[:disabled]
      ]
      |> Enum.filter(fn {_k, v} -> v end)
      |> Enum.map(fn {k, _v} -> {k, now()} end)

    if fields != [], do: Repo.update_all(from(u in User, where: u.id == ^user.id), set: fields)
    Repo.reload(user)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp log_in(conn, user), do: Plug.Test.init_test_session(conn, %{user_id: user.id})

  test "a suspended user is redirected from an authenticated page to /verify", %{conn: conn} do
    suspended = user(suspended: true)
    conn = conn |> log_in(suspended) |> get(~p"/account")
    assert redirected_to(conn) == ~p"/verify"
  end

  test "a suspended user is bounced from a live route (e.g. /sites) too", %{conn: conn} do
    suspended = user(suspended: true)
    conn = conn |> log_in(suspended) |> get(~p"/sites")
    assert redirected_to(conn) == ~p"/verify"
  end

  test "the verify screen renders for a suspended user", %{conn: conn} do
    suspended = user(suspended: true)
    conn = conn |> log_in(suspended) |> get(~p"/verify")
    assert html_response(conn, 200) =~ "Confirm your email"
    assert html_response(conn, 200) =~ suspended.email
  end

  test "a normal (non-suspended) user reaches authenticated pages", %{conn: conn} do
    active = user(confirmed: true)
    conn = conn |> log_in(active) |> get(~p"/account")
    assert html_response(conn, 200)
  end

  test "a suspended user can log in with a password (session controller allows it)", %{conn: conn} do
    suspended = user(suspended: true)

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => suspended.email, "password" => "password1234"}
      })

    # Logged in (not the disabled-account rejection), then pinned to verify.
    assert get_session(conn, :user_id) == suspended.id
  end

  test "a confirmed but disabled user is still refused login", %{conn: conn} do
    disabled = user(confirmed: true, disabled: true)

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => disabled.email, "password" => "password1234"}
      })

    refute get_session(conn, :user_id)
    assert html_response(conn, 401) =~ "disabled"
  end
end
