defmodule MastheadWeb.CommandPaletteLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Content, Sites, Uploads}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "cp-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "cp#{System.unique_integer([:positive])}",
        "name" => "CP Test",
        "owner_id" => user.id
      })

    {:ok, post} = Content.create_post(site.id, %{"title" => "Harvest report"})

    {:ok, page} =
      Content.create_page(site.id, %{"title" => "Harvest guide", "format" => "markdown"})

    upload = create_upload(site, "harvest-photo.png")

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site, post: post, page: page, upload: upload}
  end

  defp create_upload(site, filename) do
    tmp = Path.join(System.tmp_dir!(), "cp-#{System.unique_integer([:positive])}.png")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: "image/png", path: tmp})

    File.rm(tmp)
    upload
  end

  # Every helper returns the palette's own markup, not the whole page: the
  # list behind the modal contains the same titles, so page-wide assertions
  # would pass (or fail) for the wrong reason.
  defp palette(lv), do: render(element(lv, "#command-palette"))

  defp open(lv) do
    lv |> element(~s(#command-palette [data-shortcut="palette"])) |> render_click()
    palette(lv)
  end

  defp type(lv, query) do
    lv |> form("#command-palette form", %{"query" => query}) |> render_change()
    palette(lv)
  end

  defp press(lv, key) do
    lv |> element("#command-palette .palette-input") |> render_keydown(%{"key" => key})
    palette(lv)
  end

  test "the palette is present but closed on load", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/posts")

    # The trigger app.js clicks on Cmd/Ctrl+K.
    assert html =~ ~s(data-shortcut="palette")
    refute html =~ "palette-input"
  end

  test "the trigger opens it", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

    html = open(lv)

    assert html =~ "palette-input"
    assert html =~ "Search this site"
  end

  test "typing finds matches across all three kinds", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    open(lv)

    html = type(lv, "harvest")

    assert html =~ "Harvest report"
    assert html =~ "Harvest guide"
    assert html =~ "harvest-photo.png"
    assert html =~ "Posts"
    assert html =~ "Pages"
    assert html =~ "Uploads"
  end

  test "results link to the right places", %{
    conn: conn,
    site: site,
    post: post,
    page: page,
    upload: upload
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    open(lv)

    html = type(lv, "harvest")

    assert html =~ ~p"/#{site.slug}/posts/#{post.id}/edit"
    assert html =~ ~p"/#{site.slug}/pages/#{page.id}/edit"
    assert html =~ ~p"/#{site.slug}/uploads/#{upload.id}"
  end

  test "an idle palette is empty apart from an invitation", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    html = open(lv)

    assert html =~ "Search posts, pages and uploads, or type a command."

    # Nothing to read past: no commands, no destinations, no content.
    refute html =~ "Commands"
    refute html =~ "Go to"
    refute html =~ "Harvest report"
    refute html =~ "harvest-photo.png"
  end

  test "commands and destinations appear once you search", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    open(lv)

    for label <- MastheadWeb.AdminLive.CommandPalette.command_labels(site) do
      assert type(lv, label) =~ label, "expected #{inspect(label)} to be findable"
    end
  end

  describe "commands" do
    test "each one links where it says", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      assert type(lv, "new post") =~ ~p"/#{site.slug}/posts/new"
      assert type(lv, "new page") =~ ~p"/#{site.slug}/pages/new"
      # "New upload" opens the dialog on arrival rather than just landing
      # next to it.
      assert type(lv, "new upload") =~ "/#{site.slug}/uploads?new=1"
    end

    test "they filter by name as you type", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      html = type(lv, "new p")

      assert html =~ "New post"
      assert html =~ "New page"
      refute html =~ "New upload"
      refute html =~ "Settings"
    end

    test "a content search that matches no command hides the group", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      html = type(lv, "harvest")

      assert html =~ "Harvest report"
      refute html =~ "Commands"
      refute html =~ "Go to"
    end

    test "every sidebar destination is reachable", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      for {label, path} <- [
            {"Overview", ~p"/#{site.slug}"},
            {"Checklist", ~p"/#{site.slug}/checklist"},
            {"Posts", ~p"/#{site.slug}/posts"},
            {"Pages", ~p"/#{site.slug}/pages"},
            {"Uploads", ~p"/#{site.slug}/uploads"},
            {"Theme", ~p"/#{site.slug}/theme"},
            {"Users", ~p"/#{site.slug}/users"},
            {"Settings", ~p"/#{site.slug}/settings"},
            {"All sites", ~p"/sites"}
          ] do
        html = type(lv, label)
        assert html =~ "Go to"
        assert html =~ ~s(href="#{path}"), "expected #{inspect(label)} to link to #{path}"
      end
    end

    test "destinations filter by name too", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      html = type(lv, "theme")

      assert html =~ "Theme"
      refute html =~ "Checklist"
    end

    test "navigating to a destination works", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      assert active_label(type(lv, "checklist")) == "Checklist"
      lv |> form("#command-palette form") |> render_submit()

      assert_redirect(lv, ~p"/#{site.slug}/checklist")
    end

    test "commands are reachable by keyboard like any other row", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      assert active_label(type(lv, "new post")) == "New post"

      lv |> form("#command-palette form") |> render_submit()

      assert_redirect(lv, ~p"/#{site.slug}/posts/new")
    end

    test "?new=1 opens the upload dialog on arrival", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads?new=1")

      assert html =~ "New upload"
      assert html =~ "dropzone"
    end

    test "the uploads page stays closed without it", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads")

      refute html =~ "dropzone"
    end
  end

  describe "recents" do
    # Stand in for the PaletteRecents hook, which reads localStorage and
    # pushes what it finds.
    defp send_recents(lv, items) do
      lv
      |> element("#command-palette")
      |> render_hook("recents", %{"items" => items})

      palette(lv)
    end

    test "recent items show above the commands on an empty query", %{
      conn: conn,
      site: site,
      post: post
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      html =
        send_recents(lv, [
          %{
            "label" => "Harvest report",
            "meta" => "Draft",
            "path" => "/#{site.slug}/posts/#{post.id}/edit"
          }
        ])

      assert html =~ "Recent"
      assert html =~ "Harvest report"
      # Recents are all an idle palette shows, so the cursor starts on one.
      assert active_label(html) == "Harvest report"
      refute html =~ "Commands"
    end

    test "recents are hidden once you type", %{conn: conn, site: site, post: post} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      send_recents(lv, [
        %{
          "label" => "Recently opened",
          "meta" => "",
          "path" => "/#{site.slug}/posts/#{post.id}/edit"
        }
      ])

      html = type(lv, "harvest")

      refute html =~ "Recent</h3>"
      refute html =~ "Recently opened"
    end

    test "paths outside this site are dropped", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      # localStorage is user-controlled input, not trusted state.
      html =
        send_recents(lv, [
          %{"label" => "Evil", "meta" => "", "path" => "https://evil.example/steal"},
          %{"label" => "Other site", "meta" => "", "path" => "/some-other-site/posts/1/edit"},
          %{"label" => "Protocol", "meta" => "", "path" => "javascript:alert(1)"}
        ])

      refute html =~ "Evil"
      refute html =~ "Other site"
      refute html =~ "Protocol"
      refute html =~ "evil.example"
      refute html =~ "Recent</h3>"
    end

    test "malformed payloads are ignored", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      lv |> element("#command-palette") |> render_hook("recents", %{"items" => "not-a-list"})

      # Still a working palette, just no recents.
      assert palette(lv) =~ "Search posts, pages and uploads"
      assert type(lv, "harvest") =~ "Harvest report"
    end
  end

  test "a query with no matches says so", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    open(lv)

    html = type(lv, "nothing-matches-this")

    assert html =~ "No matches for"
    refute html =~ "Harvest report"
  end

  test "reopening starts from a clean slate", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
    open(lv)
    assert type(lv, "harvest") =~ "Harvest report"

    lv |> element(~s(#command-palette [phx-click="close"])) |> render_click()
    html = open(lv)

    # A palette that reopens on the last search is one you must clear first.
    refute html =~ "Harvest report"
  end

  describe "closing" do
    test "Escape from the search input closes it", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      assert open(lv) =~ "palette-input"

      # Escape must be handled by the input's own binding: the input is
      # autofocused, so a window-level binding alone never sees the key.
      refute press(lv, "Escape") =~ "palette-input"
    end

    test "the shortcut toggles it shut again", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

      assert open(lv) =~ "palette-input"
      # `open/1` clicks the same trigger app.js does on Cmd/Ctrl+K.
      refute open(lv) =~ "palette-input"
      assert open(lv) =~ "palette-input"
    end

    test "toggling shut and open again clears the previous search", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      assert type(lv, "harvest") =~ "Harvest report"

      open(lv)
      refute open(lv) =~ "Harvest report"
    end

    test "clicking the backdrop closes it", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      lv |> element(~s(#command-palette [phx-click="close"])) |> render_click()

      refute palette(lv) =~ "palette-input"
    end
  end

  describe "keyboard navigation" do
    test "the first result starts highlighted", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)

      html = type(lv, "harvest")

      # Exactly one row carries the cursor, and it's the first result.
      assert count(html, "is-active") == 1
      assert active_label(html) == "Harvest report"
    end

    test "arrow keys move the cursor and it wraps around", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      type(lv, "harvest")

      # Three results: post, page, upload. Down thrice returns to the start.
      assert active_label(press(lv, "ArrowDown")) == "Harvest guide"
      assert active_label(press(lv, "ArrowDown")) == "harvest-photo.png"
      assert active_label(press(lv, "ArrowDown")) == "Harvest report"

      # Up from the first wraps to the last.
      assert active_label(press(lv, "ArrowUp")) == "harvest-photo.png"
    end

    test "other keys leave the cursor alone", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      type(lv, "harvest")

      assert active_label(press(lv, "ArrowDown")) == "Harvest guide"
      assert active_label(press(lv, "a")) == "Harvest guide"
    end

    test "typing a new query resets the cursor to the top", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      type(lv, "harvest")
      assert active_label(press(lv, "ArrowDown")) == "Harvest guide"

      assert active_label(type(lv, "harvest ")) == "Harvest report"
    end

    test "Enter opens the highlighted result", %{conn: conn, site: site, page: page} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      type(lv, "harvest")
      press(lv, "ArrowDown")

      lv |> form("#command-palette form") |> render_submit()

      assert_redirect(lv, ~p"/#{site.slug}/pages/#{page.id}/edit")
    end

    test "Enter with no results does nothing", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")
      open(lv)
      type(lv, "nothing-matches-this")

      html = lv |> form("#command-palette form") |> render_submit()

      assert html =~ "No matches for"
    end
  end

  test "pages without a site get no palette", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/sites")

    refute html =~ ~s(data-shortcut="palette")
  end

  defp count(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)

  # The label of the row currently carrying the keyboard cursor.
  defp active_label(html) do
    case Regex.run(~r/is-active[^>]*>.*?palette-item-label[^>]*>([^<]+)</s, html) do
      [_, label] -> String.trim(label)
      nil -> nil
    end
  end
end
