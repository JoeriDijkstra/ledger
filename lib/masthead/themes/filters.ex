defmodule Masthead.Themes.Filters do
  @moduledoc """
  Custom Liquid filters made available to every theme. Solid's
  `Solid.StandardFilter` set (`escape`, `default`, `date`, `size`, ...) is
  always loaded first; anything in this module takes precedence on name
  collision.

  Filters here must be pure and side-effect-free — they run inside the
  template sandbox and can't touch the database, the filesystem, or the
  request.
  """

  @doc """
  Build an asset URL given a theme's storage base and a relative file
  name:

      {{ 'logo.png' | asset_url: theme.asset_base }}
      # => "/uploads/themes/studio/1.0.0/assets/logo.png"

  Falls back to the bare filename if the base is missing (useful in tests).
  """
  def asset_url(filename, base) when is_binary(filename) and is_binary(base) do
    base
    |> String.trim_trailing("/")
    |> Kernel.<>("/")
    |> Kernel.<>(String.trim_leading(filename, "/"))
  end

  def asset_url(filename, _), do: filename

  @doc """
  JSON-encode a value so a theme can hand it to its JavaScript. The
  intended shape is a config global in the layout, read by a static asset:

      <script>window.Masthead = { tokens: {{ theme.tokens | json }} };</script>
      <script src="{{ 'app.js' | asset_url: theme.asset_base }}"></script>

  Theme `.js` files are served as static bytes and are never templated, so
  this is how per-site values reach them. Emit the config script *before*
  the asset that reads it.

  The output is escaped for embedding directly inside a `<script>` block:
  `<`, `>`, `&` and the U+2028/U+2029 line separators become `\\uXXXX`
  escapes, so a token value containing `</script>` cannot break out of the
  tag. Works on any context value, not just the token map —
  `{{ theme.tokens.nav_links | json }}`, `{{ posts | json }}`.

  Values Jason can't encode (a struct with no encoder, e.g. `posts_by_tag`)
  yield `null` rather than failing the render.
  """
  def json(value) do
    Jason.encode!(value, escape: :html_safe)
  rescue
    _ -> "null"
  end

  @doc """
  Format a `DateTime` (or anything with `to_iso8601/1`) using
  `Calendar.strftime/2`. Solid ships a `date` filter but it's geared
  toward strings/Unix timestamps and trips on `%DateTime{}` structs.

      {{ post.published_at | strftime: "%B %-d, %Y" }}
  """
  def strftime(%DateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%NaiveDateTime{} = dt, format) when is_binary(format) do
    Calendar.strftime(dt, format)
  end

  def strftime(%Date{} = d, format) when is_binary(format) do
    Calendar.strftime(d, format)
  end

  def strftime(nil, _format), do: ""
  def strftime(other, _format), do: to_string(other)

  @doc """
  ISO-8601 string for use in `<time datetime="...">`. Defensive against
  nils so templates can do `{{ post.published_at | iso8601 }}`
  unconditionally.
  """
  def iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def iso8601(%Date{} = d), do: Date.to_iso8601(d)
  def iso8601(nil), do: ""
  def iso8601(other), do: to_string(other)

  @doc """
  Keep only the posts carrying the tag with the given slug. Lets a theme use
  tagged posts as generic content blocks:

      {% assign faqs = posts | where_tag: "faq" %}
      {% for faq in faqs %}...{% endfor %}

  Non-list input (or a missing slug) yields an empty list.
  """
  def where_tag(posts, slug) when is_list(posts) and is_binary(slug) do
    Enum.filter(posts, fn post ->
      post
      |> tags_list()
      |> Enum.any?(fn tag -> Map.get(tag, "slug") == slug end)
    end)
  end

  def where_tag(_posts, _slug), do: []

  @doc """
  Filter a list of posts by a case-insensitive substring match against their
  title or excerpt:

      {% assign hits = posts | search: query %}

  A blank query returns the list unchanged.
  """
  def search(posts, query) when is_list(posts) and is_binary(query) do
    case String.trim(query) do
      "" ->
        posts

      trimmed ->
        needle = String.downcase(trimmed)

        Enum.filter(posts, fn post ->
          contains?(Map.get(post, "title"), needle) or
            contains?(Map.get(post, "excerpt"), needle)
        end)
    end
  end

  def search(posts, _query) when is_list(posts), do: posts
  def search(_posts, _query), do: []

  defp tags_list(post) do
    case Map.get(post, "tags") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp contains?(value, needle) when is_binary(value),
    do: String.contains?(String.downcase(value), needle)

  defp contains?(_value, _needle), do: false
end
