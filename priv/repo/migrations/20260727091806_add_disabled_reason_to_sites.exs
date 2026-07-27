defmodule Masthead.Repo.Migrations.AddDisabledReasonToSites do
  use Ecto.Migration

  # Why a site is offline, so re-enable-on-verify only heals the sites that
  # went offline *because* they lost their last verified member — never a site
  # an admin deliberately paused. `nil` for online sites.
  #   "no_verified_member" — auto-disabled by the member-availability cascade
  #   "admin"              — paused manually from the console
  def up do
    alter table(:sites) do
      add :disabled_reason, :string
    end

    # Existing disabled rows predate this column; the dominant historic cause is
    # the (now-removed) solo-member cascade, so classify them as auto-disabled
    # and let a member verifying heal them.
    execute(
      "UPDATE sites SET disabled_reason = 'no_verified_member' WHERE disabled_at IS NOT NULL"
    )
  end

  def down do
    alter table(:sites) do
      remove :disabled_reason
    end
  end
end
