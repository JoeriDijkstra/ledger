defmodule MastheadWeb.AdminLive.UploadShow do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Phoenix.LiveView.JS
  alias Masthead.Uploads

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    upload = Uploads.get_upload!(socket.assigns.site.id, id)

    {:ok,
     socket
     |> assign(
       upload: upload,
       page_title: upload.filename,
       rename_open?: false,
       rename_value: upload.filename,
       rename_error: nil
     )
     |> compute_snippets()}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Uploads.delete_upload(socket.assigns.upload)

    {:noreply,
     socket
     |> put_flash(:info, "Upload deleted.")
     |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/uploads")}
  end

  def handle_event("open_rename", _params, socket) do
    {:noreply,
     assign(socket,
       rename_open?: true,
       rename_value: socket.assigns.upload.filename,
       rename_error: nil
     )}
  end

  def handle_event("close_rename", _params, socket) do
    {:noreply, assign(socket, rename_open?: false, rename_error: nil)}
  end

  def handle_event("rename_change", %{"name" => name}, socket) do
    {:noreply, assign(socket, rename_value: name, rename_error: nil)}
  end

  def handle_event("rename", %{"name" => new_name}, socket) do
    case Uploads.rename(socket.assigns.upload, new_name) do
      {:ok, upload} ->
        {:noreply,
         socket
         |> assign(
           upload: upload,
           rename_open?: false,
           rename_error: nil,
           page_title: upload.filename
         )
         |> compute_snippets()
         |> put_flash(:info, "Renamed to #{upload.filename}.")}

      {:error, reason} ->
        {:noreply, assign(socket, rename_error: humanize_error(reason))}
    end
  end

  defp humanize_error(:empty), do: "Filename can't be empty."

  defp humanize_error(:invalid_chars),
    do: "Filename can't contain slashes, leading dots, or be longer than 200 characters."

  defp humanize_error(:already_exists), do: "Another file in this site already has that name."
  defp humanize_error(:unchanged), do: "That's the current filename."
  defp humanize_error(%Ecto.Changeset{}), do: "Couldn't save the new name."
  defp humanize_error(other), do: "Couldn't rename: #{inspect(other)}"

  defp compute_snippets(socket) do
    upload = socket.assigns.upload
    url = Uploads.url(upload)

    {markdown, html} =
      if Uploads.image?(upload) do
        {"![](#{url})", ~s|<img src="#{url}" alt="" />|}
      else
        # Non-image files (PDF) embed as a link, not an <img>.
        {"[#{upload.filename}](#{url})", ~s|<a href="#{url}">#{upload.filename}</a>|}
      end

    assign(socket, url: url, markdown_snippet: markdown, html_snippet: html)
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@upload.filename}
      site={@site}
      current_user={@current_user}
      action_count={@action_count}
      present_users={@present_users}
      flash={@flash}
      active={:uploads}
    >
      <:actions>
        <.link navigate={~p"/#{@site.slug}/uploads"} class="btn">&larr; All uploads</.link>
      </:actions>

      <div class="upload-show">
        <div class="upload-preview">
          <img :if={Uploads.image?(@upload)} src={@url} alt={@upload.filename} />
          <span :if={not Uploads.image?(@upload)} class="file-badge file-badge-lg">
            {file_ext(@upload.filename)}
          </span>
        </div>

        <aside class="upload-side">
          <section class="upload-side-block">
            <h3 class="section-heading">File</h3>
            <dl class="kv">
              <dt>Type</dt>
              <dd><code>{@upload.content_type}</code></dd>
              <dt>Size</dt>
              <dd>{format_bytes(@upload.byte_size)}</dd>
              <dt>Added</dt>
              <dd>{Calendar.strftime(@upload.inserted_at, "%B %-d, %Y")}</dd>
            </dl>
          </section>

          <section class="upload-side-block">
            <h3 class="section-heading">Embed snippets</h3>
            <label class="snippet">
              <span>Markdown</span>
              <input type="text" readonly value={@markdown_snippet} />
            </label>
            <button
              type="button"
              class="btn btn-primary copy-btn"
              phx-click={JS.dispatch("masthead:copy", detail: %{text: @markdown_snippet})}
            >
              Copy as Markdown
            </button>

            <label class="snippet">
              <span>HTML</span>
              <input type="text" readonly value={@html_snippet} />
            </label>
            <button
              type="button"
              class="btn btn-primary copy-btn"
              phx-click={JS.dispatch("masthead:copy", detail: %{text: @html_snippet})}
            >
              Copy as HTML
            </button>
          </section>

          <section class="upload-side-block">
            <h3 class="section-heading">Danger zone</h3>
            <button type="button" phx-click="open_rename" class="btn danger-block">
              Rename file
            </button>
            <button
              type="button"
              phx-click="delete"
              data-confirm={"Delete \"" <> @upload.filename <> "\" permanently?"}
              class="btn btn-danger danger-block"
            >
              Delete upload
            </button>
          </section>
        </aside>
      </div>

      <div
        :if={@rename_open?}
        class="dialog-backdrop"
        phx-window-keydown="close_rename"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_rename"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog">
          <header class="dialog-header">
            <h2>Rename upload</h2>
            <button type="button" phx-click="close_rename" class="dialog-close" aria-label="Close">
              &times;
            </button>
          </header>

          <form phx-submit="rename" phx-change="rename_change" class="dialog-form">
            <div class="callout callout-warning">
              <strong>Renaming changes the public URL.</strong>
              <span>Any post, page, or external link that already references the current
                file path will break. The old URL won't redirect.</span>
            </div>

            <label>
              New filename
              <input
                type="text"
                name="name"
                value={@rename_value}
                autofocus
                spellcheck="false"
                autocomplete="off"
              />
              <small class="muted">Keep the extension. No slashes, no leading dots.</small>
            </label>

            <p :if={@rename_error} class="error">{@rename_error}</p>

            <footer class="dialog-footer">
              <button type="button" phx-click="close_rename" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Rename file</button>
            </footer>
          </form>
        </div>
      </div>
    </.shell>
    """
  end

  defp format_bytes(b) when b < 1024, do: "#{b} B"
  defp format_bytes(b) when b < 1024 * 1024, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b), do: "#{Float.round(b / 1024 / 1024, 1)} MB"

  defp file_ext(filename) do
    filename |> Path.extname() |> String.trim_leading(".") |> String.upcase()
  end
end
