defmodule Masthead.Repo.Migrations.AddSuspendedAtToUsers do
  use Ecto.Migration

  # Distinct from `disabled_at`: a suspended (day-30 unconfirmed) account can
  # still log in but is pinned to the verify screen until it confirms. Keeping
  # this separate means login gating for `disabled_at` accounts is unchanged.
  def change do
    alter table(:users) do
      add :suspended_at, :utc_datetime
    end
  end
end
