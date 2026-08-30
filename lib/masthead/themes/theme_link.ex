defmodule Masthead.Themes.ThemeLink do
  @moduledoc """
  An author-defined link on a theme's marketplace listing — documentation,
  a support address, the source repository, whatever the theme needs. The
  set is dynamic: a theme has as many (or as few) as its author adds, in
  the order they choose.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # A listing link is rendered as an anchor on a page others visit, so the
  # scheme is allow-listed rather than merely format-checked.
  @schemes ~w(http https mailto)

  schema "theme_links" do
    field :label, :string
    field :url, :string
    field :position, :integer, default: 0
    belongs_to :theme, Masthead.Themes.Theme
    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:label, :url, :position, :theme_id])
    |> update_change(:label, &String.trim/1)
    |> update_change(:url, &normalize_url/1)
    |> validate_required([:label, :url, :theme_id])
    |> validate_length(:label, max: 40)
    |> validate_length(:url, max: 500)
    |> validate_scheme()
    |> assoc_constraint(:theme)
  end

  # People type "docs.example.com"; assume https rather than rejecting it.
  # Anything that already names a scheme is left alone, so validate_scheme
  # still sees (and can reject) "javascript:alert(1)".
  defp normalize_url(url) do
    url = String.trim(url)

    if url == "" or String.contains?(url, ":"), do: url, else: "https://" <> url
  end

  defp validate_scheme(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and host not in [nil, ""] ->
          []

        %URI{scheme: "mailto", path: path} when path not in [nil, ""] ->
          []

        _ ->
          [url: "must be a http(s) or mailto link"]
      end
    end)
  end

  @doc "Schemes a listing link may use."
  def schemes, do: @schemes
end
