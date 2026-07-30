defmodule Masthead.Themes.FiltersTest do
  use ExUnit.Case, async: true

  alias Masthead.Themes.Filters

  defp post(title, tags, excerpt \\ "") do
    %{"title" => title, "excerpt" => excerpt, "tags" => tags}
  end

  defp tag(slug), do: %{"name" => slug, "slug" => slug, "color" => nil}

  describe "where_tag/2" do
    setup do
      posts = [
        post("A", [tag("faq"), tag("news")]),
        post("B", [tag("news")]),
        post("C", [])
      ]

      %{posts: posts}
    end

    test "keeps only posts carrying the given tag", %{posts: posts} do
      assert ["A"] == Filters.where_tag(posts, "faq") |> Enum.map(& &1["title"])
      assert ["A", "B"] == Filters.where_tag(posts, "news") |> Enum.map(& &1["title"])
    end

    test "returns an empty list when no post matches", %{posts: posts} do
      assert Filters.where_tag(posts, "nope") == []
    end

    test "tolerates posts with a missing tags key" do
      assert Filters.where_tag([%{"title" => "X"}], "faq") == []
    end

    test "non-list input yields an empty list" do
      assert Filters.where_tag(nil, "faq") == []
      assert Filters.where_tag("not a list", "faq") == []
    end
  end

  describe "json/1" do
    test "encodes scalars, maps and lists" do
      assert Filters.json("hi") == ~s("hi")
      assert Filters.json(42) == "42"
      assert Filters.json(true) == "true"
      assert Filters.json(nil) == "null"
      assert Filters.json(%{"accent" => "#0066cc"}) == ~s({"accent":"#0066cc"})
      assert Filters.json([%{"label" => "A"}]) == ~s([{"label":"A"}])
    end

    test "escapes so a value cannot break out of a <script> block" do
      encoded = Filters.json(%{"title" => "</script><script>alert(1)</script>"})

      refute String.contains?(encoded, "</script>")
      refute String.contains?(encoded, "<script")
      assert String.contains?(encoded, "\\u003C")
    end

    test "escapes the U+2028/U+2029 separators that break JS string literals" do
      encoded = Filters.json("a b c")

      refute String.contains?(encoded, " ")
      refute String.contains?(encoded, " ")
    end

    test "round-trips back to the original value" do
      tokens = %{
        "accent" => "#0066cc",
        "show_search" => true,
        "hero" => %{"title" => "Hello <world> & \"friends\""},
        "links" => [%{"label" => "A", "url" => "/a"}]
      }

      assert Jason.decode!(Filters.json(tokens)) == tokens
    end

    test "un-encodable values yield null instead of failing the render" do
      assert Filters.json(%Masthead.Themes.TagPosts{resolver: fn _ -> [] end}) == "null"
      assert Filters.json(self()) == "null"
    end
  end

  describe "search/2" do
    setup do
      posts = [
        post("Elixir tips", [], "pattern matching"),
        post("Phoenix guide", [], "LiveView basics"),
        post("Cooking", [], "ELIXIR of life")
      ]

      %{posts: posts}
    end

    test "matches title or excerpt case-insensitively", %{posts: posts} do
      titles = Filters.search(posts, "elixir") |> Enum.map(& &1["title"])
      assert titles == ["Elixir tips", "Cooking"]
    end

    test "a blank query returns the list unchanged", %{posts: posts} do
      assert Filters.search(posts, "   ") == posts
    end

    test "a non-string query returns the list unchanged", %{posts: posts} do
      assert Filters.search(posts, nil) == posts
    end

    test "non-list input yields an empty list" do
      assert Filters.search(nil, "x") == []
    end
  end
end
