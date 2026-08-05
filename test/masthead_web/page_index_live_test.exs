defmodule MastheadWeb.PageIndexLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Content, Sites}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "pgi-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "pgi#{System.unique_integer([:positive])}",
        "name" => "PGI Test",
        "owner_id" => user.id
      })

    {:ok, draft} =
      Content.create_page(site.id, %{"title" => "About Us", "format" => "markdown"})

    {:ok, live_page} =
      Content.create_page(site.id, %{"title" => "Contact", "format" => "markdown"})

    {:ok, live_page} = Content.update_page(live_page, %{"published" => "true"})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site, draft: draft, live_page: live_page}
  end

  defp switch_filter(lv, filter) do
    lv
    |> element(~s(button[phx-click="switch_filter"][phx-value-filter="#{filter}"]))
    |> render_click()
  end

  defp search(lv, query) do
    lv
    |> form(~s(form[phx-change="search_list"]), %{"query" => query})
    |> render_change()
  end

  test "the toolbar offers search and every status filter", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/pages")

    assert html =~ ~s(phx-change="search_list")

    for {value, label} <- Content.status_filter_options() do
      assert html =~ ~s(phx-value-filter="#{value}")
      assert html =~ label
    end

    # What app.js focuses on Cmd/Ctrl+F instead of the browser find bar.
    assert html =~ ~s(data-shortcut="search")
  end

  test "Published and Draft each narrow the list", %{conn: conn, site: site} do
    {:ok, lv, html} = live(conn, ~p"/#{site.slug}/pages")
    assert html =~ "About Us"
    assert html =~ "Contact"

    html = switch_filter(lv, "published")
    assert html =~ "Contact"
    refute html =~ "About Us"

    html = switch_filter(lv, "draft")
    assert html =~ "About Us"
    refute html =~ "Contact"

    html = switch_filter(lv, "all")
    assert html =~ "About Us"
    assert html =~ "Contact"
  end

  test "search matches the page title", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages")

    html = search(lv, "contact")

    assert html =~ "Contact"
    refute html =~ "About Us"
  end

  test "filter and search both live in the URL and combine", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages")

    switch_filter(lv, "published")
    assert_patch(lv, ~p"/#{site.slug}/pages?status=published")

    search(lv, "contact")
    # `~p` encodes the param map with its keys sorted.
    assert_patch(lv, ~p"/#{site.slug}/pages?q=contact&status=published")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/pages?q=contact&status=published")
    assert html =~ "Contact"
    refute html =~ "About Us"

    # Draft + "contact" matches nothing, since Contact is published.
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/pages?q=contact&status=draft")
    assert html =~ "No pages match"
  end

  test "switching back to All drops the param from the URL", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages?status=draft")

    switch_filter(lv, "all")

    assert_patch(lv, ~p"/#{site.slug}/pages")
  end

  test "a filter matching nothing keeps the illustration", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages")

    html = search(lv, "no-such-page")

    assert html =~ "No pages match"
    assert html =~ "empty-state-illustrated"
    assert html =~ "empty-pages.svg"
    assert html =~ "Clear filter"
    # The "no pages yet" copy is for a genuinely empty site.
    refute html =~ "No pages yet"
  end

  test "an untouched empty site still gets the plain empty state", %{} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "pgi2-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, empty} =
      Sites.create_site(%{
        "slug" => "pgi2#{System.unique_integer([:positive])}",
        "name" => "Empty",
        "owner_id" => user.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    {:ok, _lv, html} = live(conn, ~p"/#{empty.slug}/pages")

    assert html =~ "No pages yet"
    refute html =~ "No pages match"
    # Nothing to search or filter yet, so no toolbar.
    refute html =~ ~s(phx-change="search_list")
  end
end
