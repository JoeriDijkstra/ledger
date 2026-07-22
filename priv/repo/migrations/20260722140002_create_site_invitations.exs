defmodule Masthead.Repo.Migrations.CreateSiteInvitations do
  use Ecto.Migration

  def change do
    create table(:site_invitations) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :token, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:site_invitations, [:token])
    create unique_index(:site_invitations, [:site_id, :email])
  end
end
