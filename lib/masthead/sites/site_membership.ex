defmodule Masthead.Sites.SiteMembership do
  @moduledoc """
  Join row linking a `Site` to a member `User`. Membership is the sole
  site↔user relationship — there is no single owner and (for now) no roles.
  Any member can invite or remove any other member.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "site_memberships" do
    belongs_to :site, Masthead.Sites.Site
    belongs_to :user, Masthead.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:site_id, :user_id])
    |> validate_required([:site_id, :user_id])
    |> assoc_constraint(:site)
    |> assoc_constraint(:user)
    |> unique_constraint([:site_id, :user_id])
  end
end
