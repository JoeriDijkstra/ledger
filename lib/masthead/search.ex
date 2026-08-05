defmodule Masthead.Search do
  @moduledoc """
  Cross-content lookup behind the admin command palette: one term matched
  against a site's posts, pages and uploads at once.

  Each kind is queried and capped independently rather than merged in SQL —
  a union would have to rank titles against filenames to decide what falls
  off the end, and the palette shows the kinds as separate groups anyway.
  Capping per kind also means a site with a thousand matching uploads still
  leaves room for its two matching posts.

  Results are the plain schema structs. Turning them into links is the
  caller's job: contexts don't know about routes.
  """

  alias Masthead.{Content, Uploads}

  @per_kind 5

  @doc """
  Searches one site's content. Returns `%{posts: [...], pages: [...],
  uploads: [...]}`, each capped at `:limit` (default #{@per_kind}).

  A blank term matches nothing rather than everything — an empty palette
  should stay empty instead of dumping the whole site into it.
  """
  def search(site_id, term, opts \\ [])

  def search(site_id, term, opts) when is_binary(term) do
    case String.trim(term) do
      "" -> empty()
      trimmed -> query(site_id, trimmed, Keyword.get(opts, :limit, @per_kind))
    end
  end

  def search(_site_id, _term, _opts), do: empty()

  @doc "True when a result set has nothing in it."
  def empty?(%{posts: [], pages: [], uploads: []}), do: true
  def empty?(%{}), do: false

  @doc "Total number of results across all kinds."
  def count(%{posts: posts, pages: pages, uploads: uploads}),
    do: length(posts) + length(pages) + length(uploads)

  defp query(site_id, term, limit) do
    %{
      posts: Content.list_posts(site_id, search: term, limit: limit),
      pages: Content.list_pages(site_id, search: term, limit: limit),
      uploads: Uploads.list_uploads(site_id, search: term, limit: limit)
    }
  end

  defp empty, do: %{posts: [], pages: [], uploads: []}
end
