defmodule Masthead.Repo.Migrations.CreateSiteMemberships do
  use Ecto.Migration

  def up do
    create table(:site_memberships) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:site_memberships, [:site_id, :user_id])
    create index(:site_memberships, [:site_id])
    create index(:site_memberships, [:user_id])

    # Backfill one membership per existing site from its current owner. Runs
    # while `sites.owner_id` still exists (it is dropped in the next migration).
    execute """
    INSERT INTO site_memberships (site_id, user_id, inserted_at, updated_at)
    SELECT id, owner_id, now(), now() FROM sites
    """
  end

  def down do
    drop table(:site_memberships)
  end
end
