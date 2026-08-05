defmodule Masthead.Uploads.Upload do
  use Ecto.Schema
  import Ecto.Changeset

  schema "uploads" do
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :path, :string
    field :thumbnail_path, :string
    belongs_to :site, Masthead.Sites.Site
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [:filename, :content_type, :byte_size, :path, :thumbnail_path, :site_id])
    |> validate_required([:filename, :content_type, :byte_size, :path, :site_id])
    |> assoc_constraint(:site)
  end
end
