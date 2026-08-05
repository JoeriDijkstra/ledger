defmodule Masthead.Content.ListFiltersTest do
  use Masthead.DataCase

  alias Masthead.{Accounts, Content, Sites}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "lf-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "lf#{System.unique_integer([:positive])}",
        "name" => "LF Site",
        "owner_id" => user.id
      })

    %{site: site}
  end

  defp titles(records), do: records |> Enum.map(& &1.title) |> Enum.sort()

  describe "list_posts/2 status filters" do
    setup %{site: site} do
      {:ok, draft} = Content.create_post(site.id, %{"title" => "Draft post"})
      {:ok, live_post} = Content.create_post(site.id, %{"title" => "Live post"})
      {:ok, live_post} = Content.update_post(live_post, %{"published" => "true"})
      %{draft: draft, live_post: live_post}
    end

    test "filter :published keeps only published posts", %{site: site} do
      assert titles(Content.list_posts(site.id, filter: :published)) == ["Live post"]
    end

    test "filter :draft keeps only unpublished posts", %{site: site} do
      assert titles(Content.list_posts(site.id, filter: :draft)) == ["Draft post"]
    end

    test "filter :all (the default) keeps both", %{site: site} do
      assert titles(Content.list_posts(site.id, filter: :all)) == ["Draft post", "Live post"]
      assert titles(Content.list_posts(site.id)) == ["Draft post", "Live post"]
    end

    test "a status filter composes with search", %{site: site} do
      {:ok, other} = Content.create_post(site.id, %{"title" => "Live notes"})
      {:ok, _} = Content.update_post(other, %{"published" => "true"})

      assert titles(Content.list_posts(site.id, filter: :published, search: "notes")) ==
               ["Live notes"]

      assert Content.list_posts(site.id, filter: :draft, search: "notes") == []
    end
  end

  describe "list_pages/2" do
    setup %{site: site} do
      {:ok, _} = Content.create_page(site.id, %{"title" => "About Us", "format" => "markdown"})

      {:ok, contact} =
        Content.create_page(site.id, %{"title" => "Contact", "format" => "markdown"})

      {:ok, _} = Content.update_page(contact, %{"published" => "true"})
      :ok
    end

    test "filter :published keeps only published pages", %{site: site} do
      assert titles(Content.list_pages(site.id, filter: :published)) == ["Contact"]
    end

    test "filter :draft keeps only unpublished pages", %{site: site} do
      assert titles(Content.list_pages(site.id, filter: :draft)) == ["About Us"]
    end

    test "no options keeps every page, ordered by title", %{site: site} do
      assert Enum.map(Content.list_pages(site.id), & &1.title) == ["About Us", "Contact"]
    end

    test "search matches the title case-insensitively", %{site: site} do
      assert titles(Content.list_pages(site.id, search: "contact")) == ["Contact"]
      assert titles(Content.list_pages(site.id, search: "ABOUT")) == ["About Us"]
      assert Content.list_pages(site.id, search: "nothing") == []
    end

    test "an empty or nil search is not a filter", %{site: site} do
      assert length(Content.list_pages(site.id, search: "")) == 2
      assert length(Content.list_pages(site.id, search: nil)) == 2
    end

    test "filter and search compose", %{site: site} do
      assert titles(Content.list_pages(site.id, filter: :published, search: "contact")) ==
               ["Contact"]

      assert Content.list_pages(site.id, filter: :draft, search: "contact") == []
    end

    test "is scoped to the site", %{site: site} do
      {:ok, other_user} =
        Accounts.register_user(%{
          "email" => "lf2-#{System.unique_integer([:positive])}@example.com",
          "password" => "password1234"
        })

      {:ok, other_site} =
        Sites.create_site(%{
          "slug" => "lf2#{System.unique_integer([:positive])}",
          "name" => "Other",
          "owner_id" => other_user.id
        })

      {:ok, _} =
        Content.create_page(other_site.id, %{"title" => "Theirs", "format" => "markdown"})

      assert titles(Content.list_pages(other_site.id)) == ["Theirs"]
      assert titles(Content.list_pages(site.id)) == ["About Us", "Contact"]
    end
  end

  test "status_filter_options/0 lists exactly the filters both queries accept", %{site: site} do
    assert Content.status_filter_options() == [
             {:all, "All"},
             {:published, "Published"},
             {:draft, "Draft"}
           ]

    for {value, _label} <- Content.status_filter_options() do
      assert is_list(Content.list_posts(site.id, filter: value))
      assert is_list(Content.list_pages(site.id, filter: value))
    end
  end
end
