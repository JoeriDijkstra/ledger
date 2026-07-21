defmodule Masthead.Repo.Migrations.RemoveStudioTailwindBuiltins do
  use Ecto.Migration

  # Only `default` stays a built-in theme. Studio and Tailwind will be
  # re-uploaded as verified marketplace themes instead. Repoint any site
  # currently on them to the default built-in, then delete the rows
  # (theme_images / theme_installs cascade via their FKs).

  def up do
    execute("""
    UPDATE sites
    SET theme_id = (SELECT id FROM themes WHERE slug = 'default' AND source = 'built_in')
    WHERE theme_id IN (
      SELECT id FROM themes WHERE slug IN ('studio', 'tailwind') AND source = 'built_in'
    )
    """)

    execute("""
    DELETE FROM themes WHERE slug IN ('studio', 'tailwind') AND source = 'built_in'
    """)
  end

  def down do
    # The built-in rows are re-created from priv/themes on the next boot's
    # seed run; there is nothing meaningful to restore here.
    :ok
  end
end
