defmodule Masthead.Accounts.UserNotification do
  @moduledoc """
  Sent-log for once-only lifecycle emails (welcome, verify warnings,
  suspension). One row per `(user_id, kind)`; the unique index turns
  "send exactly once" into an insert that either wins or no-ops on conflict.
  See `Masthead.Accounts.notify_once/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_notifications" do
    field :kind, :string
    belongs_to :user, Masthead.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :kind])
    |> validate_required([:user_id, :kind])
    |> unique_constraint([:user_id, :kind])
  end
end
