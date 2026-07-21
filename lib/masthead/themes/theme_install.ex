defmodule Masthead.Themes.ThemeInstall do
  @moduledoc """
  Records that a theme has been installed onto a site. A site's theme
  picker (on its Theme page) chooses among the built-in Default plus the
  themes installed here. Themes are installed from the marketplace in a
  site's context.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "theme_installs" do
    belongs_to :site, Masthead.Sites.Site
    belongs_to :theme, Masthead.Themes.Theme
    timestamps(type: :utc_datetime)
  end

  def changeset(install, attrs) do
    install
    |> cast(attrs, [:site_id, :theme_id])
    |> validate_required([:site_id, :theme_id])
    |> assoc_constraint(:site)
    |> assoc_constraint(:theme)
    |> unique_constraint([:site_id, :theme_id])
  end
end
