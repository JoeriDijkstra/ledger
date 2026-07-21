defmodule MastheadWeb.MarketplaceLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes}

  setup do
    Themes.Seed.run()

    user = register("viewer")
    author = register("author")

    %{user: user, author: author, conn: conn_for(user)}
  end

  defp register(prefix) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    user
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp published(user, name, opts \\ []) do
    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: name,
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    {:ok, theme} = Themes.publish_theme(theme)
    if opts[:verified], do: elem(Themes.verify_theme(theme), 1), else: theme
  end

  test "lists published themes from others with status chips", %{conn: conn, author: author} do
    _verified = published(author, "Verified One", verified: true)
    _community = published(author, "Community One")

    {:ok, _lv, html} = live(conn, ~p"/marketplace")

    assert html =~ "Verified One"
    assert html =~ "Community One"
    # Verified themes get the green chip; community themes show no badge.
    assert html =~ "chip-verified"
    refute html =~ "chip-community"
  end

  test "verified and community filters narrow the list", %{conn: conn, author: author} do
    _verified = published(author, "Verified One", verified: true)
    _community = published(author, "Community One")

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> element(~s(a[href="/marketplace/verified"])) |> render_click()
    assert html =~ "Verified One"
    refute html =~ "Community One"

    html = lv |> element(~s(a[href="/marketplace/community"])) |> render_click()
    assert html =~ "Community One"
    refute html =~ "Verified One"
  end

  test "each filter is directly linkable by URL", %{conn: conn, author: author} do
    _verified = published(author, "Verified One", verified: true)
    _community = published(author, "Community One")

    {:ok, _lv, html} = live(conn, ~p"/marketplace/verified")
    assert html =~ "Verified One"
    refute html =~ "Community One"

    {:ok, _lv, html} = live(conn, ~p"/marketplace/community")
    assert html =~ "Community One"
    refute html =~ "Verified One"
  end

  test "search narrows themes by name", %{conn: conn, author: author} do
    _sunrise = published(author, "Sunrise")
    _moonset = published(author, "Moonset")

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> form(~s(form[phx-change="search"]), %{query: "sun"}) |> render_change()

    assert html =~ "Sunrise"
    refute html =~ "Moonset"
  end

  test "does not show your own themes", %{conn: conn, user: user} do
    _own = published(user, "My Own Theme")

    {:ok, _lv, html} = live(conn, ~p"/marketplace")
    refute html =~ "My Own Theme"
  end

  test "installing in a site's context adds it to that site", %{
    conn: conn,
    user: user,
    author: author
  } do
    site = site_for(user)
    theme = published(author, "Installable")

    {:ok, lv, html} = live(conn, ~p"/marketplace?#{[for: site.slug]}")
    assert html =~ "Install"
    # The context banner names the site.
    assert html =~ site.name

    html =
      lv
      |> element(~s(button[phx-click="install"][phx-value-id="#{theme.id}"]))
      |> render_click()

    assert html =~ "Installed"
    assert MapSet.member?(Themes.installed_theme_ids(site.id), theme.id)
  end

  test "without a site context, Install opens a site picker and installs onto the chosen site",
       %{conn: conn, user: user, author: author} do
    site = site_for(user)
    theme = published(author, "Browseable")

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    # The card's Install opens the picker (no direct install without a site).
    html =
      lv
      |> element(~s(button[phx-click="open_install_picker"][phx-value-id="#{theme.id}"]))
      |> render_click()

    assert html =~ site.name

    lv
    |> element(~s(button[phx-click="install_to_site"][phx-value-site_id="#{site.id}"]))
    |> render_click()

    assert MapSet.member?(Themes.installed_theme_ids(site.id), theme.id)
  end

  test "opening the carousel shows images and navigates", %{conn: conn, author: author} do
    theme = published(author, "Gallery Theme")
    {:ok, _} = Themes.add_theme_image(theme, image_file("a.png"))
    {:ok, _} = Themes.add_theme_image(theme, image_file("b.png"))

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> element(~s(button[phx-click="open_carousel"])) |> render_click()
    assert html =~ "dialog-carousel"
    assert html =~ "1 / 2"

    html = lv |> element(~s(button[phx-value-dir="next"])) |> render_click()
    assert html =~ "2 / 2"

    html = lv |> element(~s(button[phx-click="close_carousel"]), "×") |> render_click()
    refute html =~ "dialog-carousel"
  end

  test "the My themes filter shows the user's library", %{conn: conn, user: user} do
    _own =
      elem(
        Themes.create_upload(%{
          slug: "own#{System.unique_integer([:positive])}",
          name: "My Own Theme",
          version: "1.0.0",
          storage_path: "themes/uploaded/1.0.0",
          owner_id: user.id
        }),
        1
      )

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> element(~s(a[href="/marketplace/my-themes"])) |> render_click()
    assert html =~ "Every theme you have"
    assert html =~ "My Own Theme"
  end

  test "the /marketplace/my-themes URL opens on the My themes filter", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/marketplace/my-themes")
    assert html =~ "Every theme you have"
    # The My themes filter chip is the active (primary) one.
    assert has_element?(lv, ~s(a.btn-primary[href="/marketplace/my-themes"]))
  end

  test "the site-context banner links back to the site's theme page", %{conn: conn, user: user} do
    site = site_for(user)

    {:ok, _lv, html} = live(conn, ~p"/marketplace?#{[for: site.slug]}")

    assert html =~ ~s(href="/#{site.slug}/theme")
  end

  defp site_for(user) do
    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "mk#{System.unique_integer([:positive])}",
        "name" => "MK Site",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    site
  end

  defp image_file(filename) do
    tmp = Path.join(System.tmp_dir!(), "mk-#{System.unique_integer([:positive])}-#{filename}")
    File.write!(tmp, "bytes")
    %{filename: filename, path: tmp}
  end
end
