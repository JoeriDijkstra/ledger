defmodule Masthead.Repo.Migrations.ScopeThemeInstallsToSite do
  use Ecto.Migration

  # Themes are now installed onto a SITE, not a user's account. The old
  # per-user rows can't be mapped to a specific site, so drop and recreate
  # the table site-scoped. (No released data depends on this.)

  def up do
    drop table(:theme_installs)

    create table(:theme_installs) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :theme_id, references(:themes, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:theme_installs, [:site_id, :theme_id])
    create index(:theme_installs, [:theme_id])
  end

  def down do
    drop table(:theme_installs)

    create table(:theme_installs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :theme_id, references(:themes, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:theme_installs, [:user_id, :theme_id])
    create index(:theme_installs, [:theme_id])
  end
end
