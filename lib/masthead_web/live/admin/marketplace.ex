defmodule MastheadWeb.AdminLive.Marketplace do
  @moduledoc """
  The Marketplace hub — discover, manage, and install themes. One gallery
  with a filter bar; "My themes" is just another filter (like Verified /
  Community):

    * `:all` / `:verified` / `:community` — themes published by others.
    * `:mine` — your own uploaded themes. Upload here; a card links to the
      theme manage page (`AdminLive.ThemeManage`) for description/gallery/
      publish/delete.

  Opened from the nav it's discovery-only. Opened from a site's theme page
  ("+" card → `?for=<site-slug>`) it enters that site's **install context**:
  each card gets an Install button that adds the theme to that site, which
  the site can then select on its theme page.

  `/marketplace/my-themes` is an alias that opens straight on the `:mine`
  filter (kept so existing links and the old `/themes` URL still land here).
  """
  use MastheadWeb, :live_view

  import MastheadWeb.AdminLive.Components
  alias Masthead.Sites
  alias Masthead.Themes
  alias Masthead.Themes.Package

  @max_upload_bytes 5 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       # browse
       filter: :all,
       search: "",
       carousel: nil,
       installed: MapSet.new(),
       install_site: nil,
       # site picker (install with no site context)
       install_picker_theme: nil,
       picker_sites: [],
       # my themes
       modal_open?: false,
       upload_error: nil,
       themes: []
     )
     |> allow_upload(:theme_zip,
       accept: ~w(.zip),
       max_entries: 1,
       max_file_size: @max_upload_bytes
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # The filter is the live action, so it's carried in the URL and every
    # view is linkable (/marketplace, /marketplace/verified, …). An optional
    # `?for=<site-slug>` puts the marketplace in that site's install context.
    filter = socket.assigns.live_action
    site = load_install_site(socket, params["for"])
    installed = if site, do: Themes.installed_theme_ids(site.id), else: MapSet.new()

    {:noreply,
     socket
     |> assign(
       page_title: "Marketplace",
       filter: filter,
       install_site: site,
       installed: installed
     )
     |> load_themes()}
  end

  # Load the site named by `?for=`, owner-checked. Nil (discovery mode) when
  # absent or not accessible.
  defp load_install_site(_socket, nil), do: nil
  defp load_install_site(_socket, ""), do: nil

  defp load_install_site(socket, slug) do
    user = socket.assigns.current_user

    if user.admin,
      do: Sites.get_site_for_admin_by_slug!(slug),
      else: Sites.get_user_site_by_slug!(user.id, slug)
  rescue
    Ecto.NoResultsError -> nil
  end

  # URL for each filter — the filter bar patches between these, preserving the
  # site install context (`?for=`) when present.
  defp filter_path(:all), do: ~p"/marketplace"
  defp filter_path(:verified), do: ~p"/marketplace/verified"
  defp filter_path(:community), do: ~p"/marketplace/community"
  defp filter_path(:mine), do: ~p"/marketplace/my-themes"

  defp filter_path(value, nil), do: filter_path(value)

  defp filter_path(value, %{slug: slug}),
    do: filter_path(value) <> "?" <> URI.encode_query(for: slug)

  # Load the grid for the active filter: the user's own themes for "My themes",
  # published themes from others for everything else.
  defp load_themes(%{assigns: %{filter: :mine, current_user: user}} = socket) do
    assign(socket, themes: Themes.list_themes(user.id))
  end

  defp load_themes(%{assigns: a} = socket) do
    assign(socket, themes: Themes.list_marketplace(a.current_user.id, a.filter, a.search))
  end

  # Reload after an install/uninstall/etc. — refresh the installed set too.
  defp refresh(%{assigns: %{install_site: nil}} = socket), do: load_themes(socket)

  defp refresh(%{assigns: %{install_site: site}} = socket) do
    socket |> assign(installed: Themes.installed_theme_ids(site.id)) |> load_themes()
  end

  # ---- filter / search / carousel ----

  # "My themes" sits alongside the published-theme filters; to a user it's
  # the same idea — narrow the same gallery.
  defp filter_options,
    do: [{:all, "All"}, {:verified, "Verified"}, {:community, "Community"}, {:mine, "My themes"}]

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(search: query) |> load_themes()}
  end

  def handle_event("open_carousel", %{"id" => id}, socket) do
    id = String.to_integer(id)
    theme = Enum.find(socket.assigns.themes, &(&1.id == id))

    if theme && theme.images != [] do
      {:noreply, assign(socket, carousel: %{theme: theme, images: theme.images, index: 0})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_carousel", _params, socket) do
    {:noreply, assign(socket, carousel: nil)}
  end

  def handle_event("carousel_nav", %{"dir" => dir}, socket) do
    %{images: images, index: index} = c = socket.assigns.carousel
    count = length(images)
    step = if dir == "next", do: 1, else: count - 1
    {:noreply, assign(socket, carousel: %{c | index: rem(index + step, count)})}
  end

  # ---- install / uninstall onto the site in context ----

  def handle_event("install", %{"id" => id}, socket) do
    site = socket.assigns.install_site
    theme = Themes.get_theme!(id)

    case site && Themes.install_theme(site, theme) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> put_flash(:info, "\"#{theme.name}\" installed on #{site.name}.")}

      {:error, :not_installable} ->
        {:noreply, put_flash(socket, :error, "That theme can't be installed.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("uninstall", %{"id" => id}, socket) do
    site = socket.assigns.install_site
    theme = Themes.get_theme!(id)

    case site && Themes.uninstall_theme(site, theme.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh()
         |> put_flash(:info, "\"#{theme.name}\" removed from #{site.name}.")}

      {:error, :in_use} ->
        {:noreply,
         put_flash(socket, :error, "That theme is active on the site — pick another first.")}

      _ ->
        {:noreply, socket}
    end
  end

  # ---- install with no site context: pick a site ----

  def handle_event("open_install_picker", %{"id" => id}, socket) do
    theme = Themes.get_theme!(id)
    sites = Sites.list_sites_for_user(socket.assigns.current_user.id)
    {:noreply, assign(socket, install_picker_theme: theme, picker_sites: sites)}
  end

  def handle_event("close_install_picker", _params, socket) do
    {:noreply, assign(socket, install_picker_theme: nil, picker_sites: [])}
  end

  def handle_event("install_to_site", %{"site_id" => site_id}, socket) do
    theme = socket.assigns.install_picker_theme
    site = Enum.find(socket.assigns.picker_sites, &(to_string(&1.id) == site_id))

    case theme && site && Themes.install_theme(site, theme) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(install_picker_theme: nil, picker_sites: [])
         |> put_flash(:info, "\"#{theme.name}\" installed on #{site.name}.")}

      {:error, :not_installable} ->
        {:noreply, put_flash(socket, :error, "That theme can't be installed on that site.")}

      _ ->
        {:noreply, socket}
    end
  end

  # ---- my themes: upload ----

  def handle_event("open_modal", _params, socket) do
    {:noreply, assign(socket, modal_open?: true, upload_error: nil)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, close_modal(socket)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, upload_error: nil)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :theme_zip, ref)}
  end

  def handle_event("upload", _params, socket) do
    owner_id = socket.assigns.current_user.id

    results =
      consume_uploaded_entries(socket, :theme_zip, fn %{path: path}, _entry ->
        case Package.install(path, owner_id) do
          {:ok, theme} -> {:ok, {:ok, theme}}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{:ok, theme}] ->
        {:noreply,
         socket
         |> assign(modal_open?: false, upload_error: nil)
         |> load_themes()
         |> put_flash(:info, "Theme \"#{theme.name}\" installed.")}

      [{:error, reason}] ->
        {:noreply, assign(socket, upload_error: format_error(reason))}

      [] ->
        {:noreply, assign(socket, upload_error: "Please pick a .zip file first.")}
    end
  end

  # ---- browse helpers ----

  defp first_image(%{images: [image | _]}), do: image
  defp first_image(_), do: nil

  # A tasteful Unsplash placeholder for themes with no preview images, picked
  # deterministically per theme so a card's art is stable across renders.
  @placeholder_photos ~w(
    photo-1508739773434-c26b3d09e071
    photo-1618005182384-a83a8bd57fbe
    photo-1550859492-d5da9d8e45f3
    photo-1557683316-973673baf926
    photo-1487017159836-4e23ece2e4cf
    photo-1541701494587-cb58502866ab
  )

  defp placeholder_image(%{id: id}) do
    photo = Enum.at(@placeholder_photos, rem(id, length(@placeholder_photos)))
    "https://images.unsplash.com/#{photo}?w=640&h=360&fit=crop&auto=format&q=60"
  end

  # ---- my themes helpers ----

  defp close_modal(socket) do
    refs = Enum.map(socket.assigns.uploads.theme_zip.entries, & &1.ref)

    socket =
      Enum.reduce(refs, socket, fn ref, acc ->
        cancel_upload(acc, :theme_zip, ref)
      end)

    assign(socket, modal_open?: false, upload_error: nil)
  end

  # Install control for a theme — a compact icon button. With a site in
  # context, install/uninstall act directly on that site (its active theme
  # can't be uninstalled). Without one, it opens a site picker.
  attr :theme, :map, required: true
  attr :installed, :any, required: true
  attr :install_site, :map, default: nil

  defp install_button(%{install_site: nil} = assigns) do
    ~H"""
    <button
      type="button"
      class="card-icon-btn is-primary"
      phx-click="open_install_picker"
      phx-value-id={@theme.id}
      title="Install on a site"
      aria-label={"Install #{@theme.name}"}
    >
      <.install_icon />
    </button>
    """
  end

  defp install_button(assigns) do
    ~H"""
    <button
      :if={not MapSet.member?(@installed, @theme.id)}
      type="button"
      class="card-icon-btn is-primary"
      phx-click="install"
      phx-value-id={@theme.id}
      title="Install on this site"
      aria-label={"Install #{@theme.name}"}
    >
      <.install_icon />
    </button>
    <button
      :if={MapSet.member?(@installed, @theme.id)}
      type="button"
      class="card-icon-btn is-installed"
      phx-click="uninstall"
      phx-value-id={@theme.id}
      disabled={@install_site.theme_id == @theme.id}
      title={
        if @install_site.theme_id == @theme.id,
          do: "Active theme — pick another first",
          else: "Installed — click to remove"
      }
      aria-label="Installed"
    >
      <.check_icon />
    </button>
    """
  end

  defp install_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.7"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
      />
    </svg>
    """
  end

  defp check_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.9"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
    </svg>
    """
  end

  defp edit_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.7"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125"
      />
    </svg>
    """
  end

  # Site picker shown when installing with no site in context — choose which
  # site to install the theme onto.
  attr :theme, :map, required: true
  attr :sites, :list, required: true

  defp site_picker(assigns) do
    ~H"""
    <div class="dialog-backdrop" phx-window-keydown="close_install_picker" phx-key="Escape">
      <button
        type="button"
        phx-click="close_install_picker"
        class="dialog-close-overlay"
        aria-label="Close"
        tabindex="-1"
      >
      </button>
      <div class="dialog">
        <header class="dialog-header">
          <h2>Install "{@theme.name}"</h2>
          <button
            type="button"
            phx-click="close_install_picker"
            class="dialog-close"
            aria-label="Close"
          >
            &times;
          </button>
        </header>

        <div class="dialog-form">
          <p :if={@sites == []} class="muted">
            You don't have any sites yet. Create a site first, then install a theme onto it.
          </p>
          <p :if={@sites != []} class="muted">
            Choose a site to install this theme onto. You can then select it on that site's
            theme page.
          </p>

          <ul :if={@sites != []} class="site-picker-list">
            <li :for={site <- @sites}>
              <button
                type="button"
                class="btn btn-block"
                phx-click="install_to_site"
                phx-value-site_id={site.id}
              >
                <span>{site.name}</span>
                <span class="muted">{site.slug}</span>
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp format_error(reason) do
    case reason do
      {:archive_too_large, _, _} ->
        "Archive exceeds the 5 MB size cap."

      {:too_many_files, _, max} ->
        "Archive contains more than #{max} files."

      {:uncompressed_too_large, _, _} ->
        "Archive's uncompressed contents exceed the cap."

      {:archive_invalid, _} ->
        "That doesn't look like a valid zip file."

      :manifest_missing ->
        "manifest.json is missing from the archive."

      {:manifest_invalid, msgs} ->
        "manifest.json: " <> Enum.join(msgs, "; ")

      {:template_missing, name} ->
        "templates/#{name}.liquid is missing."

      {:template_invalid, name, _} ->
        "templates/#{name}.liquid failed to parse."

      :theme_css_missing ->
        "theme.css is missing."

      {:slug_reserved, slug} ->
        "Slug \"#{slug}\" is reserved."

      {:version_not_newer, slug, old, new} ->
        "Theme \"#{slug}\" is already at #{old}; uploaded version #{new} is not newer. " <>
          "Bump the version in manifest.json to update it."

      {:version_unparseable, v} ->
        "Version \"#{v}\" isn't valid semver (e.g. 1.2.0) — required to update an existing theme."

      {:db_write, _changeset} ->
        "Could not save the theme. Check the manifest and try again."

      {:disallowed_asset, name} ->
        "Asset \"#{name}\" has an unsupported file extension."

      {:traversal, name} ->
        "Unsafe path in entry \"#{name}\"."

      {:absolute_path, name} ->
        "Absolute path in entry \"#{name}\"."

      {:backslash, name} ->
        "Windows-style path separator in entry \"#{name}\"."

      other ->
        "Upload failed: #{inspect(other)}"
    end
  end

  defp error_to_string(:too_large), do: "File is too large."
  defp error_to_string(:not_accepted), do: "Wrong file type."
  defp error_to_string(:too_many_files), do: "Too many files."
  defp error_to_string(err), do: inspect(err)

  # ---- render ----

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title={@page_title} current_user={@current_user} flash={@flash} active={:marketplace}>
      <:actions>
        <a
          :if={@filter == :mine}
          href="https://github.com/JoeriDijkstra/masthead-template"
          target="_blank"
          rel="noopener"
          class="github-btn"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M12 .5C5.6.5.5 5.6.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.2.8-.6v-2c-3.2.7-3.9-1.4-3.9-1.4-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.7 1.3 3.4 1 .1-.8.4-1.3.8-1.6-2.6-.3-5.3-1.3-5.3-5.8 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2 1-.3 2-.4 3-.4s2 .1 3 .4c2.3-1.5 3.3-1.2 3.3-1.2.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.1 0 4.5-2.7 5.5-5.3 5.8.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6 4.6-1.5 7.9-5.9 7.9-10.9C23.5 5.6 18.4.5 12 .5z" />
          </svg>
          <span>Theme template</span>
        </a>
        <button
          :if={@filter == :mine}
          type="button"
          phx-click="open_modal"
          class="btn btn-primary"
        >
          + Upload theme
        </button>
      </:actions>

      <div :if={@install_site} class="marketplace-context-bar">
        <span>
          Adding a theme to <strong>{@install_site.name}</strong> — install one below, then
          pick it on the theme page.
        </span>
        <.link navigate={~p"/#{@install_site.slug}/theme"} class="btn btn-sm">
          ← Back to theme settings
        </.link>
      </div>

      <p :if={is_nil(@install_site)} class="page-intro">
        {if @filter == :mine do
          "Every theme you have — built-ins and your uploads. Upload your own Liquid packages and publish them to the marketplace for others to use."
        else
          "Discover themes the community has published. Open the marketplace from a site's theme page to install one onto that site."
        end}
      </p>

      <div class="admin-toolbar">
        <div class="admin-toolbar-row">
          <div class="admin-filters">
            <.link
              :for={{value, label} <- filter_options()}
              patch={filter_path(value, @install_site)}
              class={["btn btn-sm", @filter == value && "btn-primary"]}
            >
              {label}
            </.link>
          </div>
          <form :if={@filter != :mine} phx-change="search" class="admin-search">
            <input
              type="search"
              name="query"
              value={@search}
              placeholder="Search themes…"
              phx-debounce="300"
              autocomplete="off"
            />
          </form>
        </div>
      </div>

      <%= if @filter == :mine do %>
        {my_themes_body(assigns)}
      <% else %>
        {browse_body(assigns)}
      <% end %>

      <.carousel_modal :if={@carousel} carousel={@carousel} />
      <.site_picker
        :if={@install_picker_theme}
        theme={@install_picker_theme}
        sites={@picker_sites}
      />
      <.upload_modal :if={@modal_open?} uploads={@uploads} upload_error={@upload_error} />
    </.shell>
    """
  end

  # ---- browse body (published themes from others) ----

  defp browse_body(assigns) do
    ~H"""
    <div>
      <div :if={@themes == []} class="empty-state">
        <img src={~p"/images/illustrations/empty-themes.svg"} alt="" class="empty-illustration" />
        <h2>Nothing here yet</h2>
        <p>
          {cond do
            @search != "" -> "No themes match \"#{@search}\"."
            @filter == :verified -> "No verified themes yet."
            @filter == :community -> "No community themes yet."
            true -> "No themes have been published to the marketplace yet."
          end}
        </p>
      </div>

      <ul :if={@themes != []} class="marketplace-grid">
        <li :for={t <- @themes} id={"marketplace-card-#{t.id}"}>
          <article class="marketplace-card">
            <div class="marketplace-thumb">
              <button
                :if={first_image(t)}
                type="button"
                class="marketplace-thumb-btn"
                phx-click="open_carousel"
                phx-value-id={t.id}
                aria-label={"View #{t.name} images"}
              >
                <img src={Themes.image_url(first_image(t))} alt={"#{t.name} preview"} />
                <span class="marketplace-thumb-zoom" aria-hidden="true">⤢</span>
              </button>
              <img
                :if={is_nil(first_image(t))}
                class="marketplace-thumb-placeholder"
                src={placeholder_image(t)}
                alt=""
                aria-hidden="true"
                loading="lazy"
              />
              <div class="marketplace-card-tags">
                <.theme_badge theme={t} />
                <span class="chip chip-accent theme-card-version">v{t.version}</span>
              </div>
            </div>
            <div class="marketplace-card-meta">
              <div class="marketplace-card-id">
                <h3>{t.name}</h3>
              </div>
              <div class="marketplace-card-actions">
                <.install_button theme={t} installed={@installed} install_site={@install_site} />
              </div>
            </div>
          </article>
        </li>
      </ul>
    </div>
    """
  end

  # ---- my themes body (the user's library + management) ----

  defp my_themes_body(assigns) do
    ~H"""
    <div>
      <div :if={@themes == []} class="empty-state">
        <img src={~p"/images/illustrations/empty-themes.svg"} alt="" class="empty-illustration" />
        <h2>No themes yet</h2>
        <p>Upload a Liquid theme package to get started.</p>
        <button type="button" phx-click="open_modal" class="btn btn-primary">+ Upload theme</button>
      </div>

      <ul :if={@themes != []} class="marketplace-grid">
        <li :for={t <- @themes} id={"theme-card-#{t.id}"}>
          <article class="marketplace-card">
            <div class="marketplace-thumb">
              <img
                :if={first_image(t)}
                src={Themes.image_url(first_image(t))}
                alt={"#{t.name} preview"}
              />
              <img
                :if={is_nil(first_image(t))}
                class="marketplace-thumb-placeholder"
                src={placeholder_image(t)}
                alt=""
                aria-hidden="true"
                loading="lazy"
              />
              <div class="marketplace-card-tags">
                <span class={["chip", if(t.public, do: "chip-marketplace", else: "chip-neutral")]}>
                  {if t.public, do: "Published", else: "Draft"}
                </span>
                <span class="chip chip-accent theme-card-version">v{t.version}</span>
              </div>
            </div>
            <div class="marketplace-card-meta">
              <div class="marketplace-card-id">
                <h3>{t.name}</h3>
              </div>
              <div class="marketplace-card-actions">
                <.link
                  navigate={~p"/marketplace/my-themes/#{t.id}"}
                  class="card-icon-btn"
                  title="Edit theme"
                  aria-label={"Edit #{t.name}"}
                >
                  <.edit_icon />
                </.link>
                <.install_button theme={t} installed={@installed} install_site={@install_site} />
              </div>
            </div>
          </article>
        </li>

        <li>
          <button type="button" phx-click="open_modal" class="marketplace-card marketplace-card-add">
            <span class="marketplace-card-add-icon" aria-hidden="true">+</span>
            <span class="marketplace-card-add-label">Upload theme</span>
          </button>
        </li>
      </ul>
    </div>
    """
  end

  # ---- modals & icons (function components) ----

  defp carousel_modal(assigns) do
    ~H"""
    <div class="dialog-backdrop" phx-window-keydown="close_carousel" phx-key="Escape">
      <button
        type="button"
        phx-click="close_carousel"
        class="dialog-close-overlay"
        aria-label="Close"
        tabindex="-1"
      >
      </button>
      <div class="dialog dialog-carousel">
        <header class="dialog-header">
          <div class="dialog-title">
            <h2>{@carousel.theme.name}</h2>
            <div class="theme-card-tags">
              <.theme_badge theme={@carousel.theme} />
              <span class="chip chip-accent theme-card-version">v{@carousel.theme.version}</span>
            </div>
          </div>
          <button type="button" phx-click="close_carousel" class="dialog-close" aria-label="Close">
            &times;
          </button>
        </header>

        <div class="carousel">
          <button
            :if={length(@carousel.images) > 1}
            type="button"
            class="carousel-nav carousel-prev"
            phx-click="carousel_nav"
            phx-value-dir="prev"
            aria-label="Previous image"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
            </svg>
          </button>

          <div class="carousel-stage">
            <img
              src={Themes.image_url(Enum.at(@carousel.images, @carousel.index))}
              alt={"#{@carousel.theme.name} preview #{@carousel.index + 1}"}
            />
          </div>

          <button
            :if={length(@carousel.images) > 1}
            type="button"
            class="carousel-nav carousel-next"
            phx-click="carousel_nav"
            phx-value-dir="next"
            aria-label="Next image"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
          </button>
        </div>

        <p :if={length(@carousel.images) > 1} class="carousel-counter">
          {@carousel.index + 1} / {length(@carousel.images)}
        </p>
      </div>
    </div>
    """
  end

  defp upload_modal(assigns) do
    ~H"""
    <div class="dialog-backdrop" phx-window-keydown="close_modal" phx-key="Escape">
      <button
        type="button"
        phx-click="close_modal"
        class="dialog-close-overlay"
        aria-label="Close"
        tabindex="-1"
      >
      </button>
      <div class="dialog">
        <header class="dialog-header">
          <h2>Upload theme</h2>
          <button type="button" phx-click="close_modal" class="dialog-close" aria-label="Close">
            &times;
          </button>
        </header>

        <form id="theme-upload-form" phx-submit="upload" phx-change="validate" class="dialog-form">
          <label class="dropzone" phx-drop-target={@uploads.theme_zip.ref}>
            <svg
              class="dropzone-icon"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 7.5m0 0L7.5 12m4.5-4.5v12"
              />
            </svg>
            <.live_file_input upload={@uploads.theme_zip} />
            <p class="dropzone-headline">Drop a theme .zip here, or click to browse</p>
            <p class="muted">Up to 5 MB. Must contain a manifest, templates, and theme.css.</p>
          </label>

          <ul :if={@uploads.theme_zip.entries != []} class="upload-entries">
            <li :for={entry <- @uploads.theme_zip.entries}>
              <span class="entry-name">{entry.client_name}</span>
              <span class="muted entry-progress">{entry.progress}%</span>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="btn btn-sm"
              >
                Remove
              </button>
              <p :for={err <- upload_errors(@uploads.theme_zip, entry)} class="error entry-error">
                {error_to_string(err)}
              </p>
            </li>
          </ul>

          <p :for={err <- upload_errors(@uploads.theme_zip)} class="error">
            {error_to_string(err)}
          </p>
          <p :if={@upload_error} class="error">{@upload_error}</p>

          <footer class="dialog-footer">
            <button type="button" phx-click="close_modal" class="btn">Cancel</button>
            <button type="submit" class="btn btn-primary" disabled={@uploads.theme_zip.entries == []}>
              Install
            </button>
          </footer>
        </form>
      </div>
    </div>
    """
  end
end
