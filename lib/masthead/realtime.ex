defmodule Masthead.Realtime do
  @moduledoc """
  Per-site PubSub topics + typed broadcast/subscribe helpers for the live
  admin. Contexts call the `*_changed` helpers after a successful mutation;
  admin LiveViews (and the shared `:load_site` hook) subscribe to the topics
  they care about and react in `handle_info/2`.

  All messages are tagged tuples under `:realtime` so they never collide with
  the LiveViews' existing local `{:file_picked, ...}` messages.
  """
  @pubsub Masthead.PubSub

  # ---- topics ----

  def actions_topic(site_id), do: "site:#{site_id}:actions"
  def content_topic(site_id), do: "site:#{site_id}:content"
  def members_topic(site_id), do: "site:#{site_id}:members"
  def settings_topic(site_id), do: "site:#{site_id}:settings"
  def lifecycle_topic(site_id), do: "site:#{site_id}:lifecycle"
  def presence_topic(site_id), do: "site:#{site_id}:presence"
  def user_topic(user_id), do: "user:#{user_id}"

  def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  # ---- broadcasts (fire-and-forget) ----

  @doc "The site's pending todo count changed (badge + checklist)."
  def actions_changed(site_id), do: broadcast(actions_topic(site_id), {:realtime, :actions})

  @doc """
  A post or page changed. `meta` is `%{kind: :post | :page, id:, op: :created
  | :updated | :deleted, updated_at:}` — index/dashboard views reload; open
  editors use it to detect an external change to the record they're editing.
  """
  def content_changed(site_id, meta),
    do: broadcast(content_topic(site_id), {:realtime, :content, meta})

  @doc "The site's members or pending invitations changed."
  def members_changed(site_id), do: broadcast(members_topic(site_id), {:realtime, :members})

  @doc "The site's settings or tags changed."
  def settings_changed(site_id), do: broadcast(settings_topic(site_id), {:realtime, :settings})

  @doc "The site was soft-deleted — everyone viewing it should leave."
  def site_gone(site_id), do: broadcast(lifecycle_topic(site_id), {:realtime, :site_gone})

  @doc "`user_id` lost access to `site_id` (removed from it) — bounce their open tabs on that site."
  def access_revoked(user_id, site_id),
    do: broadcast(user_topic(user_id), {:realtime, :access_revoked, site_id})

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)
end
