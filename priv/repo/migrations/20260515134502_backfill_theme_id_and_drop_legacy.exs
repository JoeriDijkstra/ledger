defmodule Masthead.Repo.Migrations.BackfillThemeIdAndDropLegacy do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Cuts sites over from the legacy `theme :string` column to the new
  `theme_id` foreign key.

  Steps:
    1. Seed built-in theme rows from `priv/themes/` so the FK target rows
       exist.
    2. UPDATE sites.theme_id from sites.theme. Unknown legacy values fall
       back to the `default` theme.
    3. Mark sites.theme_id NOT NULL.
    4. Drop the legacy sites.theme column.
  """

  def up do
    # Seeding + backfill only matters for an existing database that still has
    # sites carrying the legacy `theme` string. A fresh database (CI, a new
    # dev machine, a from-scratch migrate) has no sites to backfill, and its
    # built-in theme rows are created at application boot — so we skip the
    # seed there. (Seeding here calls the live `Themes` context, which selects
    # columns added by *later* migrations; running it on a fresh schema would
    # fail. Guarding on the presence of sites avoids that entirely.)
    if Masthead.Repo.aggregate(from(s in "sites", select: s.id), :count) > 0 do
      # 1. Seed built-ins (idempotent — safe to run inside a migration).
      Masthead.Themes.Seed.run()

      # Cache the built-in slug → id lookup once.
      built_ins =
        Masthead.Repo.all(
          from(t in "themes", where: t.source == "built_in", select: {t.slug, t.id})
        )
        |> Map.new()

      default_id =
        Map.get(built_ins, "default") ||
          raise "default theme not seeded — cannot backfill"

      # 2. Backfill sites.theme_id.
      Enum.each(built_ins, fn {slug, id} ->
        execute(
          "UPDATE sites SET theme_id = #{id} WHERE theme = '#{escape(slug)}' AND theme_id IS NULL"
        )
      end)

      # Anything that doesn't match a known built-in falls back to default.
      execute("UPDATE sites SET theme_id = #{default_id} WHERE theme_id IS NULL")
    end

    # 3. Make NOT NULL (safe on an empty sites table too).
    alter table(:sites) do
      modify :theme_id, :bigint, null: false
    end

    # 4. Drop the legacy column.
    alter table(:sites) do
      remove :theme
    end
  end

  def down do
    alter table(:sites) do
      add :theme, :string, default: "default", null: false
    end

    execute("""
    UPDATE sites SET theme = COALESCE(
      (SELECT slug FROM themes WHERE themes.id = sites.theme_id),
      'default'
    )
    """)

    alter table(:sites) do
      modify :theme_id, :bigint, null: true
    end
  end

  defp escape(s) when is_binary(s), do: String.replace(s, "'", "''")
end
