defmodule Masthead.Repo.Migrations.CreateUserNotifications do
  use Ecto.Migration

  # Sent-log for once-only lifecycle emails (welcome, day-16/23 warnings,
  # suspension). One row per `(user_id, kind)`; the unique index makes
  # "send exactly once" an insert that either wins or no-ops on conflict.
  def change do
    create table(:user_notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_notifications, [:user_id, :kind])
  end
end
