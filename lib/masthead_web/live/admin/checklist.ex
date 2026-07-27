defmodule MastheadWeb.AdminLive.Checklist do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.Actions

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site

    {:ok,
     socket
     |> assign(page_title: "Checklist — #{site.name}")
     |> assign_actions()}
  end

  @impl true
  def handle_event("dismiss_action", %{"key" => key}, socket) do
    :ok = Actions.dismiss_action(socket.assigns.site, key)
    {:noreply, assign_actions(socket)}
  end

  @impl true
  def handle_info({:realtime, :actions}, socket), do: {:noreply, assign_actions(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_actions(socket) do
    actions = Actions.list_pending(socket.assigns.site)
    assign(socket, actions: actions, action_count: length(actions))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title="Checklist"
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:checklist}
      action_count={@action_count}
      present_users={@present_users}
    >
      <div :if={@actions == []} class="empty-state empty-state-illustrated">
        <img
          src={~p"/images/illustrations/empty-checklist.svg"}
          alt=""
          class="empty-illustration"
        />
        <h2>You're all caught up</h2>
        <p>There are no outstanding actions for this site.</p>
      </div>

      <div :if={@actions != []} class="action-list">
        <.action_card :for={action <- @actions} action={action} />
      </div>
    </.shell>
    """
  end
end
