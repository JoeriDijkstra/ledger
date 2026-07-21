defmodule MastheadWeb.MyThemesLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "lib-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    theme = upload(user, "My Theme")

    %{user: user, theme: theme, conn: conn_for(user)}
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp upload(user, name) do
    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: name,
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    theme
  end

  test "/themes redirects to the My Themes tab", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/marketplace/my-themes"}}} = live(conn, ~p"/themes")
  end

  test "each theme card links to its manage page", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes")

    assert has_element?(lv, ~s(a[href="/marketplace/my-themes/#{theme.id}"]))
  end

  test "my themes lists built-ins and your own uploads, not others' themes", %{conn: conn} do
    {:ok, author} =
      Accounts.register_user(%{
        "email" => "auth-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    other = upload(author, "Someone Elses")
    {:ok, _} = Themes.publish_theme(other)

    {:ok, _lv, html} = live(conn, ~p"/marketplace/my-themes")

    assert html =~ "My Theme"
    refute html =~ "Someone Elses"
  end
end
