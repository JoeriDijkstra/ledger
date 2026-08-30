defmodule Masthead.Repo.Migrations.CreateThemeLinks do
  use Ecto.Migration

  def change do
    create table(:theme_links) do
      add :theme_id, references(:themes, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :url, :string, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:theme_links, [:theme_id])
    create index(:theme_links, [:theme_id, :position])
  end
end
