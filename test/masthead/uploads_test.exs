defmodule Masthead.UploadsTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Sites, Uploads}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "up-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "up#{System.unique_integer([:positive])}",
        "name" => "Up Test",
        "owner_id" => user.id
      })

    %{site: site}
  end

  defp store(site, filename, content_type) do
    tmp = Path.join(System.tmp_dir!(), "ut-#{System.unique_integer([:positive])}")
    File.write!(tmp, "bytes")

    result =
      Uploads.store_image(site, %{filename: filename, content_type: content_type, path: tmp})

    File.rm(tmp)
    result
  end

  test "accepts PDF uploads", %{site: site} do
    assert {:ok, upload} = store(site, "doc.pdf", "application/pdf")
    assert upload.content_type == "application/pdf"
    refute Uploads.image?(upload)
  end

  test "accepts .ico uploads", %{site: site} do
    assert {:ok, upload} = store(site, "favicon.ico", "image/x-icon")
    assert Uploads.image?(upload)
  end

  test "accepts .ico by extension even when the browser sends a blank MIME", %{site: site} do
    assert {:ok, _upload} = store(site, "favicon.ico", "")
  end

  test "still rejects unsupported types", %{site: site} do
    assert {:error, :unsupported_type} = store(site, "evil.exe", "application/x-msdownload")
  end

  test "image?/1 classifies common types" do
    assert Uploads.image?("image/png")
    assert Uploads.image?("image/svg+xml")
    refute Uploads.image?("application/pdf")
    refute Uploads.image?(nil)
  end

  describe "list_uploads/2" do
    test "returns every upload for the site by default", %{site: site} do
      {:ok, _} = store(site, "one.png", "image/png")
      {:ok, _} = store(site, "two.png", "image/png")

      assert length(Uploads.list_uploads(site.id)) == 2
    end

    test "search matches the filename case-insensitively", %{site: site} do
      {:ok, _} = store(site, "Hero-Banner.png", "image/png")
      {:ok, _} = store(site, "footer.png", "image/png")

      assert [%{filename: "Hero-Banner.png"}] =
               Uploads.list_uploads(site.id, search: "hero")

      assert [] = Uploads.list_uploads(site.id, search: "nothing-here")
    end

    test "an empty or nil search is not a filter", %{site: site} do
      {:ok, _} = store(site, "one.png", "image/png")

      assert length(Uploads.list_uploads(site.id, search: "")) == 1
      assert length(Uploads.list_uploads(site.id, search: nil)) == 1
    end

    test "limit caps the rows returned, newest first", %{site: site} do
      for n <- 1..5, do: {:ok, _} = store(site, "file-#{n}.png", "image/png")

      capped = Uploads.list_uploads(site.id, limit: 3)

      assert length(capped) == 3
      # inserted_at has second resolution, so these all tie — the id
      # tiebreaker still puts the newest three first, in a stable order.
      assert Enum.map(capped, & &1.filename) == ["file-5.png", "file-4.png", "file-3.png"]
    end

    test "filter :images keeps only what renders in an <img>", %{site: site} do
      {:ok, _} = store(site, "pic.png", "image/png")
      {:ok, _} = store(site, "vector.svg", "image/svg+xml")
      {:ok, _} = store(site, "doc.pdf", "application/pdf")

      names = site.id |> Uploads.list_uploads(filter: :images) |> Enum.map(& &1.filename)

      assert Enum.sort(names) == ["pic.png", "vector.svg"]
    end

    test "filter :documents keeps everything that is not an image", %{site: site} do
      {:ok, _} = store(site, "pic.png", "image/png")
      {:ok, _} = store(site, "doc.pdf", "application/pdf")

      assert [%{filename: "doc.pdf"}] = Uploads.list_uploads(site.id, filter: :documents)
    end

    test "filter :all (the default) keeps both", %{site: site} do
      {:ok, _} = store(site, "pic.png", "image/png")
      {:ok, _} = store(site, "doc.pdf", "application/pdf")

      assert length(Uploads.list_uploads(site.id, filter: :all)) == 2
      assert length(Uploads.list_uploads(site.id)) == 2
    end

    test "filter_options/0 covers every filter the query accepts", %{site: site} do
      {:ok, _} = store(site, "pic.png", "image/png")

      for {value, label} <- Uploads.filter_options() do
        assert is_binary(label)
        assert is_list(Uploads.list_uploads(site.id, filter: value))
      end
    end

    test "search, filter and limit compose", %{site: site} do
      for n <- 1..4, do: {:ok, _} = store(site, "report-#{n}.png", "image/png")
      {:ok, _} = store(site, "report.pdf", "application/pdf")
      {:ok, _} = store(site, "other.png", "image/png")

      found = Uploads.list_uploads(site.id, search: "report", filter: :images, limit: 2)

      assert length(found) == 2
      assert Enum.all?(found, &String.starts_with?(&1.filename, "report-"))
    end

    test "is scoped to the site", %{site: site} do
      {:ok, other_user} =
        Accounts.register_user(%{
          "email" => "other-#{System.unique_integer([:positive])}@example.com",
          "password" => "password1234"
        })

      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "other#{System.unique_integer([:positive])}",
          "name" => "Other",
          "owner_id" => other_user.id
        })

      {:ok, _} = store(site, "mine.png", "image/png")
      {:ok, _} = store(other_site, "theirs.png", "image/png")

      assert [%{filename: "mine.png"}] = Uploads.list_uploads(site.id)
      assert [%{filename: "theirs.png"}] = Uploads.list_uploads(other_site.id)
    end
  end
end
