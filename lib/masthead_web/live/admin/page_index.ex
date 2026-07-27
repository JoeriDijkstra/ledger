defmodule MastheadWeb.AdminLive.PageIndex do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.{Content, Realtime}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Realtime.subscribe(Realtime.content_topic(socket.assigns.site.id))
    {:ok, load(socket)}
  end

  @impl true
  def handle_info({:realtime, :content, _meta}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    page = Content.get_page!(socket.assigns.site.id, id)
    {:ok, _} = Content.delete_page(page)

    {:noreply,
     socket
     |> put_flash(:info, "Page deleted.")
     |> load()}
  end

  defp load(socket) do
    pages = Content.list_pages(socket.assigns.site.id)
    assign(socket, pages: pages, page_title: "Pages — #{socket.assigns.site.name}")
  end

  defp format_label(%{format: "theme", template: t}) when is_binary(t),
    do: t |> String.replace(["-", "_"], " ") |> String.capitalize()

  defp format_label(%{format: format}), do: format_label(format)
  defp format_label("markdown"), do: "Markdown"
  defp format_label("html"), do: "HTML"
  defp format_label("theme"), do: "Theme page"
  defp format_label(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title="Pages"
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:pages}
      action_count={@action_count}
      present_users={@present_users}
    >
      <:actions>
        <.link navigate={~p"/#{@site.slug}/pages/import"} class="btn btn-add">
          <span class="btn-add-icon" aria-hidden="true">↑</span>
          <span class="btn-add-label">Import</span>
        </.link>
        <.link
          navigate={~p"/#{@site.slug}/pages/new"}
          class="btn btn-primary btn-add"
          data-shortcut="new"
        >
          <span class="btn-add-icon" aria-hidden="true">+</span>
          <span class="btn-add-label">New page</span>
        </.link>
      </:actions>

      <table :if={@pages != []} class="table table-cards">
        <thead>
          <tr>
            <th>Title</th>
            <th>Format</th>
            <th>Status</th>
            <th>Updated</th>
            <th class="actions-cell"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={p <- @pages}
            class="row-link"
            phx-click={JS.navigate(~p"/#{@site.slug}/pages/#{p.id}/edit")}
          >
            <td>
              <span class="row-title">{p.title}</span>
              <div class="muted">/{p.slug}</div>
            </td>
            <td data-label="Format">
              <span class={"format-tag format-tag-" <> p.format}>{format_label(p)}</span>
            </td>
            <td data-label="Status">
              <span class={"pill pill-" <> if(p.published, do: "live", else: "draft")}>
                {if p.published, do: "Published", else: "Draft"}
              </span>
            </td>
            <td data-label="Updated"><.relative_time at={p.updated_at} /></td>
            <td class="actions-cell">
              <div class="row-actions">
                <button
                  type="button"
                  phx-click={JS.navigate(~p"/#{@site.slug}/pages/#{p.id}/edit")}
                  class="btn btn-sm"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={p.id}
                  data-confirm={"Delete page \"" <> p.title <> "\"?"}
                  class="btn btn-danger btn-sm"
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@pages == []} class="empty-state empty-state-illustrated">
        <img src={~p"/images/illustrations/empty-pages.svg"} alt="" class="empty-illustration" />
        <h2>No pages yet</h2>
        <p>
          Pages are standalone content such as About or Contact. Published pages appear in the site navigation.
        </p>
        <.link navigate={~p"/#{@site.slug}/pages/new"} class="btn btn-primary">+ New page</.link>
      </div>
    </.shell>
    """
  end
end
