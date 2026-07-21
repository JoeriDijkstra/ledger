defmodule MastheadWeb.AdminLive.ThemeManage do
  @moduledoc """
  Manage one of your uploaded themes: edit its description, manage the
  marketplace preview gallery, publish/unpublish it, and delete it. Reached
  from a theme's card under "My themes". Owner (or platform admin) only.
  """
  use MastheadWeb, :live_view

  import MastheadWeb.AdminLive.Components
  alias Masthead.Themes

  @max_image_bytes 8 * 1024 * 1024

  @impl true
  def mount(%{"theme_id" => id}, _session, socket) do
    theme = Themes.get_theme!(id)
    user = socket.assigns.current_user

    if theme.source == "uploaded" and (theme.owner_id == user.id or user.admin) do
      {:ok,
       socket
       |> assign(
         page_title: "Manage — #{theme.name}",
         theme: theme,
         images: Themes.list_theme_images(theme.id),
         description_form: to_form(Themes.change_details(theme)),
         preview_error: nil
       )
       |> allow_upload(:preview,
         accept: ~w(.png .jpg .jpeg .gif .webp),
         max_entries: 8,
         max_file_size: @max_image_bytes
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "You can only manage your own themes.")
       |> redirect(to: ~p"/marketplace/my-themes")}
    end
  rescue
    Ecto.NoResultsError ->
      {:ok,
       socket
       |> put_flash(:error, "Theme not found.")
       |> redirect(to: ~p"/marketplace/my-themes")}
  end

  # ---- description ----

  @impl true
  def handle_event("validate_description", %{"theme" => params}, socket) do
    form = to_form(Themes.change_details(socket.assigns.theme, params), action: :validate)
    {:noreply, assign(socket, description_form: form)}
  end

  def handle_event("save_description", %{"theme" => params}, socket) do
    case Themes.update_details(socket.assigns.theme, params) do
      {:ok, theme} ->
        {:noreply,
         socket
         |> assign(theme: theme, description_form: to_form(Themes.change_details(theme)))
         |> put_flash(:info, "Description saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, description_form: to_form(changeset, action: :validate))}
    end
  end

  # ---- gallery ----

  def handle_event("validate_preview", _params, socket) do
    {:noreply, assign(socket, preview_error: nil)}
  end

  def handle_event("cancel-preview", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :preview, ref)}
  end

  def handle_event("save_previews", _params, socket) do
    theme = socket.assigns.theme

    results =
      consume_uploaded_entries(socket, :preview, fn %{path: path}, entry ->
        case Themes.add_theme_image(theme, %{filename: entry.client_name, path: path}) do
          {:ok, _image} -> {:ok, :ok}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    cond do
      results == [] ->
        {:noreply, assign(socket, preview_error: "Pick at least one image first.")}

      Enum.any?(results, &match?({:error, _}, &1)) ->
        {:noreply,
         socket
         |> assign(images: Themes.list_theme_images(theme.id))
         |> assign(preview_error: "Some images couldn't be saved.")}

      true ->
        {:noreply, assign(socket, images: Themes.list_theme_images(theme.id), preview_error: nil)}
    end
  end

  def handle_event("reorder_previews", %{"ids" => ids}, socket) do
    theme = socket.assigns.theme
    Themes.reorder_theme_images(theme.id, Enum.map(ids, &String.to_integer/1))
    {:noreply, assign(socket, images: Themes.list_theme_images(theme.id))}
  end

  def handle_event("remove_preview", %{"id" => id}, socket) do
    theme = socket.assigns.theme
    image = Masthead.Repo.get!(Masthead.Themes.ThemeImage, id)

    if image.theme_id == theme.id do
      {:ok, _} = Themes.delete_theme_image(image)
      {:noreply, assign(socket, images: Themes.list_theme_images(theme.id))}
    else
      {:noreply, socket}
    end
  end

  # ---- publish / delete ----

  def handle_event("publish", _params, socket) do
    {:ok, theme} = Themes.publish_theme(socket.assigns.theme)

    {:noreply,
     socket
     |> assign(theme: theme)
     |> put_flash(:info, "\"#{theme.name}\" is live on the marketplace.")}
  end

  def handle_event("unpublish", _params, socket) do
    {:ok, theme} = Themes.unpublish_theme(socket.assigns.theme)

    {:noreply,
     socket
     |> assign(theme: theme)
     |> put_flash(:info, "\"#{theme.name}\" was removed from the marketplace.")}
  end

  def handle_event("delete", _params, socket) do
    theme = socket.assigns.theme

    case Themes.delete_theme(theme) do
      {:ok, _} ->
        Themes.Loader.invalidate(theme.id)

        {:noreply,
         socket
         |> put_flash(:info, "Theme deleted.")
         |> redirect(to: ~p"/marketplace/my-themes")}

      {:error, {:in_use, names}} ->
        {:noreply, put_flash(socket, :error, theme_in_use_message(names))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete theme.")}
    end
  end

  defp theme_in_use_message(names) do
    count = length(names)
    site_word = if count == 1, do: "site", else: "sites"

    "Can't delete this theme — it's still installed on #{count} #{site_word}: " <>
      "#{Enum.join(names, ", ")}. Remove it there first."
  end

  defp error_to_string(:too_large), do: "File is too large."
  defp error_to_string(:not_accepted), do: "Wrong file type."
  defp error_to_string(:too_many_files), do: "Too many files."
  defp error_to_string(err), do: inspect(err)

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title={@theme.name} current_user={@current_user} flash={@flash} active={:marketplace}>
      <:title_meta>
        <span class="chip chip-accent theme-card-version">v{@theme.version}</span>
        <span class={["chip", if(@theme.public, do: "chip-marketplace", else: "chip-neutral")]}>
          {if @theme.public, do: "Published", else: "Draft"}
        </span>
        <.theme_badge theme={@theme} />
      </:title_meta>
      <:actions>
        <.link navigate={~p"/marketplace/my-themes"} class="btn">← Back to my themes</.link>
      </:actions>

      <div class="form settings-form">
        <section class="settings-section">
          <header class="settings-section-head">
            <h2>Description</h2>
            <p>Shown on your theme's marketplace listing.</p>
          </header>
          <div class="settings-fields">
            <.form
              for={@description_form}
              phx-change="validate_description"
              phx-submit="save_description"
              class="manage-description-form"
            >
              <textarea
                id={@description_form[:description].id}
                name={@description_form[:description].name}
                rows="3"
                placeholder="Describe your theme…"
              >{Phoenix.HTML.Form.normalize_value("textarea", @description_form[:description].value)}</textarea>
              <p :for={{msg, _} <- @description_form[:description].errors} class="error">{msg}</p>
              <div>
                <button type="submit" class="btn btn-primary">Save description</button>
              </div>
            </.form>
          </div>
        </section>

        <section class="settings-section">
          <header class="settings-section-head">
            <h2>Preview images</h2>
            <p>
              The marketplace shows these front and center. Drag to reorder — the first
              image leads the listing.
            </p>
          </header>
          <div class="settings-fields">
            <ul
              :if={@images != []}
              id="preview-sortable"
              phx-hook="SortableList"
              data-sortable-event="reorder_previews"
              class="preview-list"
            >
              <li
                :for={img <- @images}
                id={"preview-row-#{img.id}"}
                draggable="true"
                data-sortable-id={img.id}
                class="preview-row"
              >
                <span class="preview-drag" aria-hidden="true"><.drag_handle_icon /></span>
                <img src={Themes.image_url(img)} alt={"#{@theme.name} preview"} class="preview-thumb" />
                <span class="preview-row-spacer"></span>
                <button
                  type="button"
                  class="btn btn-sm btn-danger"
                  phx-click="remove_preview"
                  phx-value-id={img.id}
                  data-confirm="Remove this image?"
                >
                  Remove
                </button>
              </li>
            </ul>

            <form id="preview-upload-form" phx-submit="save_previews" phx-change="validate_preview">
              <label class="dropzone" id="preview-dropzone" phx-hook="ImageCompress">
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
                <input type="file" multiple accept="image/*" class="js-image-picker" />
                <.live_file_input upload={@uploads.preview} />
                <p class="dropzone-headline">Drop preview images here, or click to browse</p>
                <p class="muted">
                  PNG, JPG, GIF or WebP. Large images are compressed automatically. Up to 8 images.
                </p>
              </label>

              <ul :if={@uploads.preview.entries != []} class="upload-entries">
                <li :for={entry <- @uploads.preview.entries}>
                  <span class="entry-name">{entry.client_name}</span>
                  <span class="muted entry-progress">{entry.progress}%</span>
                  <button
                    type="button"
                    phx-click="cancel-preview"
                    phx-value-ref={entry.ref}
                    class="btn btn-sm"
                  >
                    Remove
                  </button>
                  <p :for={err <- upload_errors(@uploads.preview, entry)} class="error entry-error">
                    {error_to_string(err)}
                  </p>
                </li>
              </ul>

              <p :for={err <- upload_errors(@uploads.preview)} class="error">
                {error_to_string(err)}
              </p>
              <p :if={@preview_error} class="error">{@preview_error}</p>

              <div class="manage-upload-submit">
                <button type="submit" class="btn" disabled={@uploads.preview.entries == []}>
                  Add images
                </button>
              </div>
            </form>
          </div>
        </section>

        <section class="settings-section">
          <header class="settings-section-head">
            <h2>Marketplace</h2>
            <p>
              {if @theme.public,
                do: "Your theme is public — anyone can find and install it.",
                else: "Publish to let others find and install your theme."}
            </p>
          </header>
          <div class="settings-fields">
            <div>
              <button
                :if={not @theme.public}
                type="button"
                phx-click="publish"
                class="btn btn-primary"
              >
                Publish to marketplace
              </button>
              <button :if={@theme.public} type="button" phx-click="unpublish" class="btn">
                Unpublish
              </button>
            </div>
          </div>
        </section>

        <section class="settings-section danger-zone">
          <header class="settings-section-head">
            <h2>Delete theme</h2>
            <p>
              Permanently delete this theme and its preview images. A theme installed on
              any site must be removed there first.
            </p>
          </header>
          <div class="settings-fields">
            <div class="danger-row">
              <button
                type="button"
                phx-click="delete"
                class="btn btn-danger"
                data-confirm={"Delete \"#{@theme.name}\"? This can't be undone."}
              >
                Delete theme
              </button>
            </div>
          </div>
        </section>
      </div>
    </.shell>
    """
  end

  defp drag_handle_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M9 5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm0 7a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm-1.5 8.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM18 5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm-1.5 8.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm0 7a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z" />
    </svg>
    """
  end
end
