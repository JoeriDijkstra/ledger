defmodule MastheadWeb.MyThemesLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Repo, Themes}

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

  test "each theme card links to its detail page", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes")

    assert has_element?(lv, ~s(a[href="/marketplace/themes/#{theme.id}"]))
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

  test "uploading a theme lands on its detail page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/marketplace/my-themes")

    lv |> element(~s(button.btn-primary[phx-click="open_modal"])) |> render_click()

    slug = "up#{System.unique_integer([:positive])}"

    input =
      file_input(lv, "#theme-upload-form", :theme_zip, [
        %{name: "#{slug}.zip", content: File.read!(theme_zip(slug)), type: "application/zip"}
      ])

    render_upload(input, "#{slug}.zip")

    assert {:error, {:live_redirect, %{to: path}}} =
             lv |> form("#theme-upload-form") |> render_submit()

    theme = Repo.get_by!(Themes.Theme, slug: slug)
    assert path == "/marketplace/themes/#{theme.id}"
  end

  defp theme_zip(slug) do
    files = %{
      "manifest.json" =>
        Jason.encode!(%{"name" => "Demo #{slug}", "slug" => slug, "version" => "1.0.0"}),
      "templates/layout.liquid" => "<html><head></head><body>{{ content }}</body></html>",
      "templates/index.liquid" => "<h1>{{ site.name | escape }}</h1>",
      "templates/post.liquid" => "<article>{{ body_html }}</article>",
      "templates/page.liquid" => "<article>{{ body_html }}</article>",
      "templates/blog.liquid" => "<h1>{{ page.title | escape }}</h1>",
      "templates/not_found.liquid" => "<h1>Not found</h1>",
      "theme.css" => "body { background: white; }"
    }

    path = Path.join(System.tmp_dir!(), "#{slug}.zip")
    entries = Enum.map(files, fn {name, body} -> {String.to_charlist(name), body} end)
    {:ok, _} = :zip.create(String.to_charlist(path), entries)
    path
  end
end
