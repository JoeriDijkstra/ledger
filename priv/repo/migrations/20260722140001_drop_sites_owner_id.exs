defmodule Masthead.Repo.Migrations.DropSitesOwnerId do
  use Ecto.Migration

  def up do
    drop index(:sites, [:owner_id])
    alter table(:sites), do: remove(:owner_id)
  end

  def down do
    # Rollback re-adds the column (nullable — the original owner is not
    # recoverable from memberships, so we can't restore the NOT NULL default).
    alter table(:sites) do
      add :owner_id, references(:users, on_delete: :restrict)
    end

    create index(:sites, [:owner_id])
  end
end
