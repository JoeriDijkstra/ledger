defmodule MastheadWeb.UploadShowLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Uploads}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "us-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "us#{System.unique_integer([:positive])}",
        "name" => "US Test",
        "owner_id" => user.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  defp create_upload(site, filename, content_type) do
    tmp = Path.join(System.tmp_dir!(), "us-#{System.unique_integer([:positive])}")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: content_type, path: tmp})

    File.rm(tmp)
    upload
  end

  test "a PDF is rendered in an inline viewer", %{conn: conn, site: site} do
    upload = create_upload(site, "handbook.pdf", "application/pdf")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads/#{upload.id}")

    assert html =~ ~s(type="application/pdf")
    assert html =~ "pdf-viewer"
    assert html =~ Uploads.url(upload)
  end

  test "the viewer carries a fallback for browsers that can't render PDFs", %{
    conn: conn,
    site: site
  } do
    upload = create_upload(site, "handbook.pdf", "application/pdf")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads/#{upload.id}")

    assert html =~ "pdf-fallback"
    assert html =~ "Open in a new tab"
    # The fallback link must be safe to open cross-tab.
    assert html =~ ~s(rel="noopener")
  end

  test "an image still renders as an image, not a PDF viewer", %{conn: conn, site: site} do
    upload = create_upload(site, "photo.png", "image/png")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads/#{upload.id}")

    assert html =~ ~s(<img)
    refute html =~ "pdf-viewer"
    refute html =~ ~s(type="application/pdf")
  end

  test "a PDF still embeds as a link, not an <img>", %{conn: conn, site: site} do
    upload = create_upload(site, "handbook.pdf", "application/pdf")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/uploads/#{upload.id}")

    # Being viewable in the admin doesn't make a PDF an image in a theme.
    assert html =~ "[handbook.pdf]("
    refute html =~ "![]("
  end
end
