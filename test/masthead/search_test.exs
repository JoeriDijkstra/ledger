defmodule Masthead.SearchTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Content, Search, Sites, Uploads}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "se-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "se#{System.unique_integer([:positive])}",
        "name" => "Search Site",
        "owner_id" => user.id
      })

    %{site: site}
  end

  defp create_upload(site, filename) do
    tmp = Path.join(System.tmp_dir!(), "se-#{System.unique_integer([:positive])}.png")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: "image/png", path: tmp})

    File.rm(tmp)
    upload
  end

  describe "search/3" do
    test "finds matches across all three kinds at once", %{site: site} do
      {:ok, _} = Content.create_post(site.id, %{"title" => "Harvest report"})
      {:ok, _} = Content.create_page(site.id, %{"title" => "Harvest", "format" => "markdown"})
      create_upload(site, "harvest-photo.png")

      results = Search.search(site.id, "harvest")

      assert [%{title: "Harvest report"}] = results.posts
      assert [%{title: "Harvest"}] = results.pages
      assert [%{filename: "harvest-photo.png"}] = results.uploads
      assert Search.count(results) == 3
      refute Search.empty?(results)
    end

    test "matches case-insensitively", %{site: site} do
      {:ok, _} = Content.create_post(site.id, %{"title" => "Harvest report"})

      assert [_] = Search.search(site.id, "HARVEST").posts
    end

    test "a term that matches nothing returns empty groups", %{site: site} do
      {:ok, _} = Content.create_post(site.id, %{"title" => "Harvest report"})

      results = Search.search(site.id, "nothing-matches")

      assert Search.empty?(results)
      assert Search.count(results) == 0
    end

    test "a blank term matches nothing rather than everything", %{site: site} do
      {:ok, _} = Content.create_post(site.id, %{"title" => "Harvest report"})
      create_upload(site, "photo.png")

      for term <- ["", "   ", nil] do
        assert Search.empty?(Search.search(site.id, term)),
               "expected #{inspect(term)} to match nothing"
      end
    end

    test "each kind is capped independently", %{site: site} do
      for n <- 1..8, do: {:ok, _} = Content.create_post(site.id, %{"title" => "note #{n}"})
      for n <- 1..8, do: create_upload(site, "note-#{n}.png")
      {:ok, _} = Content.create_page(site.id, %{"title" => "note page", "format" => "markdown"})

      results = Search.search(site.id, "note", limit: 5)

      # A flood of uploads must not crowd out the single matching page.
      assert length(results.posts) == 5
      assert length(results.uploads) == 5
      assert length(results.pages) == 1
    end

    test "is scoped to the site", %{site: site} do
      {:ok, other_user} =
        Accounts.register_user(%{
          "email" => "se2-#{System.unique_integer([:positive])}@example.com",
          "password" => "password1234"
        })

      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "se2#{System.unique_integer([:positive])}",
          "name" => "Other",
          "owner_id" => other_user.id
        })

      {:ok, _} = Content.create_post(other_site.id, %{"title" => "Secret roadmap"})

      assert Search.empty?(Search.search(site.id, "roadmap"))
      assert [_] = Search.search(other_site.id, "roadmap").posts
    end

    test "finds drafts as well as published content", %{site: site} do
      {:ok, draft} = Content.create_post(site.id, %{"title" => "Draft idea"})
      refute draft.published

      assert [_] = Search.search(site.id, "draft idea").posts
    end
  end
end
