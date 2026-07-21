defmodule Masthead.Repo.Migrations.AddPriceCentsToThemes do
  use Ecto.Migration

  # Foundation for future paid themes. `0` means free (the default for every
  # existing theme).
  def change do
    alter table(:themes) do
      add :price_cents, :integer, null: false, default: 0
    end
  end
end
