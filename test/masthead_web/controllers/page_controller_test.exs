defmodule MastheadWeb.PageControllerTest do
  use MastheadWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "A publishing engine for content-driven websites."
  end

  test "GET / renders SEO metadata", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(<meta name="description")
    assert html =~ "open-source, multi-tenant publishing platform"
    assert html =~ ~s(rel="canonical")
    assert html =~ ~s(property="og:title")
    assert html =~ ~s(name="twitter:card")
  end

  test "GET / embeds JSON-LD structured data for answer engines", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(<script type="application/ld+json")
    assert html =~ "SoftwareApplication"
    assert html =~ "FAQPage"
    # Visible FAQ content must be present so it matches the FAQPage schema.
    assert html =~ "What is Masthead?"
    assert html =~ "Can I use my own domain?"
  end
end
