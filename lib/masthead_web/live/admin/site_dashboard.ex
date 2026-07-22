defmodule MastheadWeb.AdminLive.SiteDashboard do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.{Actions, Content, Realtime}

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site

    if connected?(socket) do
      Realtime.subscribe(Realtime.content_topic(site.id))
      Realtime.subscribe(Realtime.settings_topic(site.id))
    end

    {:ok, load(socket)}
  end

  defp load(socket) do
    site = socket.assigns.site

    assign(socket,
      posts: Content.list_posts(site.id),
      pages: Content.list_pages(site.id),
      top_action: Actions.top_action(site),
      page_title: site.name
    )
  end

  @impl true
  def handle_info({:realtime, :content, _meta}, socket), do: {:noreply, load(socket)}
  def handle_info({:realtime, :settings}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@site.name}
      site={@site}
      current_user={@current_user}
      action_count={@action_count}
      present_users={@present_users}
      flash={@flash}
      active={:overview}
    >
      <:actions>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary btn-add">
          <span class="btn-add-icon" aria-hidden="true">+</span>
          <span class="btn-add-label">New post</span>
        </.link>
      </:actions>

      <h2 :if={@top_action} class="section-heading">Pending</h2>
      <.action_card :if={@top_action} action={@top_action} dismissible={false} />

      <h2 class="section-heading">Statistics</h2>

      <section class="metrics">
        <div class="metric"><span class="num">{length(@posts)}</span> posts</div>
        <div class="metric">
          <span class="num">{Enum.count(@posts, & &1.published)}</span> published
        </div>
        <div class="metric"><span class="num">{length(@pages)}</span> pages</div>
      </section>

      <h2 class="section-heading">Recent posts</h2>

      <div :if={@posts == []} class="empty-state empty-state-illustrated">
        <img src={~p"/images/illustrations/empty-posts.svg"} alt="" class="empty-illustration" />
        <h2>No posts yet</h2>
        <p>
          Create your first post to start publishing. Drafts remain private until you publish them.
        </p>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary">+ New post</.link>
      </div>

      <ul :if={@posts != []} class="recent-list">
        <li :for={p <- Enum.take(@posts, 5)}>
          <.link navigate={~p"/#{@site.slug}/posts/#{p.id}/edit"}>
            <strong>{p.title}</strong>
            <span class={"pill pill-" <> if(p.published, do: "live", else: "draft")}>
              {if p.published, do: "Published", else: "Draft"}
            </span>
          </.link>
        </li>
      </ul>

      <p :if={length(@posts) > 5} style="margin-top: 0.75rem;">
        <.link navigate={~p"/#{@site.slug}/posts"}>See all posts &rarr;</.link>
      </p>
    </.shell>
    """
  end
end
