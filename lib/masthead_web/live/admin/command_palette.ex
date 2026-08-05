defmodule MastheadWeb.AdminLive.CommandPalette do
  @moduledoc """
  Cmd/Ctrl+K search over the current site's posts, pages and uploads, plus a
  short list of jump-to commands.

  Rendered once by `AdminLive.Components.shell/1`, so every site-scoped
  admin page gets it without wiring anything up. It is self-contained: it
  runs its own search and navigates on its own, so the host LiveView needs
  no `handle_info` clause.

  Opening is deliberately not a JS-only affair. `app.js` clicks the hidden
  `data-shortcut="palette"` trigger, reusing the same mechanism as the
  save/publish/new shortcuts rather than inventing a second one.

  An idle palette shows only recently opened items, kept in the browser's
  localStorage by the `CommandPalette` hook. Typing searches content and
  filters the commands and sidebar destinations by name.

  Keyboard: Cmd/Ctrl+K toggles it open and shut, type to search, Up/Down to
  move, Enter to open the highlighted row, Escape to close.
  """
  use MastheadWeb, :live_component

  alias Masthead.Search

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(recents: []) |> reset()}
  end

  # Cmd/Ctrl+K toggles: the same keystroke that opened the palette closes it
  # again, so the shortcut is a switch rather than a one-way door.
  @impl true
  def handle_event("toggle", _params, socket) do
    if socket.assigns.open? do
      {:noreply, close(socket)}
    else
      {:noreply, socket |> reset() |> assign(open?: true)}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search(socket.assigns.site.id, query)
    {:noreply, assign(socket, query: query, results: results, cursor: 0)}
  end

  # Escape is handled here, on the input, and not only by the backdrop's
  # phx-window-keydown: the input is autofocused, and a keydown consumed by
  # the focused element's own binding never reaches the window one. (The
  # input also carries no phx-debounce — LiveView swallows Escape on a
  # debounced input to cancel the pending change.)
  def handle_event("key", %{"key" => "Escape"}, socket), do: {:noreply, close(socket)}
  def handle_event("key", %{"key" => "ArrowDown"}, socket), do: {:noreply, move(socket, 1)}
  def handle_event("key", %{"key" => "ArrowUp"}, socket), do: {:noreply, move(socket, -1)}
  def handle_event("key", _params, socket), do: {:noreply, socket}

  def handle_event("go", _params, socket) do
    case Enum.at(entries(socket.assigns), socket.assigns.cursor) do
      nil ->
        {:noreply, socket}

      entry ->
        # Mouse clicks are recorded by the hook straight from the anchor;
        # keyboard selection never touches one, so echo it back instead.
        socket = close(socket)

        socket =
          if entry.record?,
            do: push_event(socket, "palette:record", Map.take(entry, [:label, :meta, :path])),
            else: socket

        {:noreply, push_navigate(socket, to: entry.path)}
    end
  end

  # Recents come from the browser, so they are input, not state: keep only
  # rows that point somewhere inside this site's admin.
  def handle_event("recents", %{"items" => items}, socket) when is_list(items) do
    {:noreply, assign(socket, recents: Enum.filter(items, &own_path?(&1, socket.assigns.site)))}
  end

  def handle_event("recents", _params, socket), do: {:noreply, socket}

  defp own_path?(%{"path" => path}, site) when is_binary(path),
    do: String.starts_with?(path, "/#{site.slug}/")

  defp own_path?(_item, _site), do: false

  defp close(socket), do: assign(socket, open?: false)

  # Always open on a clean slate: a palette that reopens showing the last
  # search is a palette you have to clear before you can use it.
  defp reset(socket),
    do: assign(socket, open?: false, query: "", results: Search.search(nil, ""), cursor: 0)

  defp move(socket, delta) do
    case length(entries(socket.assigns)) do
      0 -> socket
      count -> assign(socket, cursor: Integer.mod(socket.assigns.cursor + delta, count))
    end
  end

  # ---- rows ----

  # Things that create something.
  defp actions(site),
    do: [
      {"New post", ~p"/#{site.slug}/posts/new"},
      {"New page", ~p"/#{site.slug}/pages/new"},
      # Opens the upload dialog on arrival rather than landing beside it.
      {"New upload", ~p"/#{site.slug}/uploads?new=1"}
    ]

  # Every destination in the sidebar, so the palette is a way to get around
  # and not only a way to find content. "View site" is left out: it is an
  # external link, which `.link navigate` cannot do.
  defp destinations(site),
    do: [
      {"Overview", ~p"/#{site.slug}"},
      {"Checklist", ~p"/#{site.slug}/checklist"},
      {"Posts", ~p"/#{site.slug}/posts"},
      {"Pages", ~p"/#{site.slug}/pages"},
      {"Uploads", ~p"/#{site.slug}/uploads"},
      {"Theme", ~p"/#{site.slug}/theme"},
      {"Users", ~p"/#{site.slug}/users"},
      {"Settings", ~p"/#{site.slug}/settings"},
      {"All sites", ~p"/sites"}
    ]

  @doc false
  def command_labels(site), do: Enum.map(actions(site) ++ destinations(site), &elem(&1, 0))

  defp match(pairs, query) do
    term = query |> String.trim() |> String.downcase()

    pairs
    |> Enum.filter(fn {label, _path} ->
      term == "" or String.contains?(String.downcase(label), term)
    end)
    # `record?: false` — commands and destinations are always on screen with
    # an empty query, so remembering them would just duplicate the row below.
    |> Enum.map(fn {label, path} -> %{label: label, meta: "", path: path, record?: false} end)
  end

  # Groups in render order. The cursor indexes the flattened list, so this is
  # the single source of truth for both what is drawn and what Enter opens.
  defp groups(assigns) do
    %{results: results, site: site, query: query, recents: recents} = assigns

    # An idle palette shows where you have been, nothing else. Commands and
    # destinations are a search away rather than a wall to read past.
    if String.trim(query) == "" do
      [{"Recent", Enum.map(recents, &recent_entry/1)}]
    else
      [
        {"Commands", match(actions(site), query)},
        {"Go to", match(destinations(site), query)},
        {"Posts", Enum.map(results.posts, &entry(:post, &1, site))},
        {"Pages", Enum.map(results.pages, &entry(:page, &1, site))},
        {"Uploads", Enum.map(results.uploads, &entry(:upload, &1, site))}
      ]
    end
    |> Enum.reject(fn {_title, entries} -> entries == [] end)
  end

  defp entries(assigns), do: assigns |> groups() |> Enum.flat_map(fn {_t, es} -> es end)

  # Recents are re-recorded on use, so opening one bumps it back to the top.
  defp recent_entry(%{"label" => label} = item),
    do: %{
      label: label,
      meta: Map.get(item, "meta") || "",
      path: Map.fetch!(item, "path"),
      record?: true
    }

  defp entry(:post, post, site),
    do: %{
      label: post.title,
      meta: if(post.published, do: "Published", else: "Draft"),
      path: ~p"/#{site.slug}/posts/#{post.id}/edit",
      record?: true
    }

  defp entry(:page, page, site),
    do: %{
      label: page.title,
      meta: "/#{page.slug}",
      path: ~p"/#{site.slug}/pages/#{page.id}/edit",
      record?: true
    }

  defp entry(:upload, upload, site),
    do: %{
      label: upload.filename,
      meta: format_bytes(upload.byte_size),
      path: ~p"/#{site.slug}/uploads/#{upload.id}",
      record?: true
    }

  defp format_bytes(b) when b < 1024, do: "#{b} B"
  defp format_bytes(b) when b < 1024 * 1024, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b), do: "#{Float.round(b / 1024 / 1024, 1)} MB"

  # Pair every group with the flat index its first row occupies, so a row can
  # tell whether it is the one the cursor is on.
  defp indexed_groups(assigns) do
    assigns
    |> groups()
    |> Enum.map_reduce(0, fn {title, entries}, offset ->
      {{title, Enum.with_index(entries, offset)}, offset + length(entries)}
    end)
    |> elem(0)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :indexed_groups, indexed_groups(assigns))

    ~H"""
    <%!-- phx-target so the hook's pushEventTo reaches this component rather
          than the host LiveView, which knows nothing about recents. --%>
    <div id={@id} phx-hook="CommandPalette" phx-target={@myself}>
      <%!-- Hidden trigger: app.js clicks this on Cmd/Ctrl+K. Keeping the
            opening in the same data-shortcut system as save/publish/new
            means the palette needs no bespoke JS of its own. --%>
      <button
        type="button"
        data-shortcut="palette"
        phx-click="toggle"
        phx-target={@myself}
        class="visually-hidden"
        tabindex="-1"
        aria-label="Open search"
      >
      </button>

      <div
        :if={@open?}
        class="dialog-backdrop palette-backdrop"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <button
          type="button"
          phx-click="close"
          phx-target={@myself}
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>

        <div class="dialog palette">
          <form phx-change="search" phx-submit="go" phx-target={@myself} class="palette-form">
            <input
              type="text"
              name="query"
              value={@query}
              placeholder="Search posts, pages and uploads…"
              autocomplete="off"
              phx-keydown="key"
              phx-target={@myself}
              phx-mounted={JS.focus()}
              class="palette-input"
              aria-label="Search this site"
            />
          </form>

          <div :if={@indexed_groups == [] and @query != ""} class="palette-empty">
            No matches for “{@query}”.
          </div>

          <div :if={@indexed_groups == [] and @query == ""} class="palette-empty">
            Search posts, pages and uploads, or type a command.
          </div>

          <div :if={@indexed_groups != []} class="palette-results">
            <section :for={{title, entries} <- @indexed_groups} class="palette-group">
              <h3 class="palette-group-title">{title}</h3>
              <ul>
                <li :for={{entry, i} <- entries}>
                  <.link
                    navigate={entry.path}
                    class={["palette-item", @cursor == i && "is-active"]}
                    aria-current={@cursor == i && "true"}
                    data-label={entry.label}
                    data-meta={entry.meta}
                    data-record={entry.record? && "1"}
                  >
                    <span class="palette-item-label">{entry.label}</span>
                    <span class="palette-item-meta">{entry.meta}</span>
                  </.link>
                </li>
              </ul>
            </section>
          </div>

          <footer class="palette-footer">
            <span><kbd>↑</kbd><kbd>↓</kbd> to move</span>
            <span><kbd>↵</kbd> to open</span>
            <span><kbd>esc</kbd> to close</span>
          </footer>
        </div>
      </div>
    </div>
    """
  end
end
