defmodule MastheadWeb.ThemeManageLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "mg-#{System.unique_integer([:positive])}@example.com",
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

  defp image_file(filename) do
    tmp = Path.join(System.tmp_dir!(), "mg-#{System.unique_integer([:positive])}-#{filename}")
    File.write!(tmp, "bytes")
    %{filename: filename, path: tmp}
  end

  test "saving a description updates the theme", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes/#{theme.id}")

    lv
    |> form("form[phx-submit=save_description]", theme: %{description: "A lovely theme."})
    |> render_submit()

    assert Themes.get_theme!(theme.id).description == "A lovely theme."
  end

  test "publishing and unpublishing toggles public", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes/#{theme.id}")

    html = lv |> element("button", "Publish to marketplace") |> render_click()
    assert html =~ "Unpublish"
    assert Themes.get_theme!(theme.id).public

    lv |> element("button", "Unpublish") |> render_click()
    refute Themes.get_theme!(theme.id).public
  end

  test "reordering the gallery persists the new order", %{conn: conn, theme: theme} do
    {:ok, a} = Themes.add_theme_image(theme, image_file("a.png"))
    {:ok, b} = Themes.add_theme_image(theme, image_file("b.png"))

    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes/#{theme.id}")

    lv
    |> element("#preview-sortable")
    |> render_hook("reorder_previews", %{"ids" => ["#{b.id}", "#{a.id}"]})

    assert Themes.list_theme_images(theme.id) |> Enum.map(& &1.id) == [b.id, a.id]
  end

  test "removing a gallery image deletes it", %{conn: conn, theme: theme} do
    {:ok, img} = Themes.add_theme_image(theme, image_file("a.png"))

    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes/#{theme.id}")

    lv
    |> element(~s(button[phx-click="remove_preview"][phx-value-id="#{img.id}"]))
    |> render_click()

    assert Themes.list_theme_images(theme.id) == []
  end

  test "deleting the theme removes it and redirects", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes/#{theme.id}")

    assert {:error, {:redirect, %{to: "/marketplace/my-themes"}}} =
             lv |> element("button", "Delete theme") |> render_click()

    refute Themes.get_theme(theme.id)
  end

  test "you can't manage someone else's theme", %{theme: theme} do
    {:ok, other} =
      Accounts.register_user(%{
        "email" => "other-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    conn = conn_for(other)

    assert {:error, {:redirect, %{to: "/marketplace/my-themes"}}} =
             live(conn, ~p"/marketplace/my-themes/#{theme.id}")
  end
end
