defmodule Masthead.Repo.Migrations.AddThumbnailPathToUploads do
  use Ecto.Migration

  def change do
    # Storage path of a generated preview image (today: page 1 of a PDF,
    # rasterized by `Masthead.Uploads.Thumbnail`). Null means no preview:
    # either the type has none, or generation is queued or failed.
    alter table(:uploads) do
      add :thumbnail_path, :string
    end
  end
end
