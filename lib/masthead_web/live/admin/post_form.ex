defmodule MastheadWeb.AdminLive.PostForm do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.{Content, Realtime}
  alias Masthead.Content.Post

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket),
      do: Realtime.subscribe(Realtime.content_topic(socket.assigns.site.id))

    {post, draft, page_title, step} =
      case socket.assigns.live_action do
        :new ->
          {nil, %{"format" => "markdown"}, "New post", 1}

        :import ->
          # Step 0 is the file-picker screen. Once a file is imported we seed
          # the draft and jump to step 2 (a single file) or create drafts
          # outright (multiple files).
          {nil, %{"format" => "markdown"}, "Import posts", 0}

        :edit ->
          post = Content.get_post!(socket.assigns.site.id, params["id"])
          # Open existing posts directly on the content step — most edits
          # are body tweaks; format and details are reachable via Back.
          {post, post_to_draft(post), "Edit: #{post.title}", 3}
      end

    {:ok,
     socket
     |> assign(
       post: post,
       step: step,
       draft: draft,
       page_title: page_title,
       slug_touched: post != nil,
       show_errors: false,
       external_change: nil,
       tags: Content.list_tags(socket.assigns.site.id)
     )
     |> maybe_allow_import()
     |> assign_changeset(draft)}
  end

  defp maybe_allow_import(%{assigns: %{live_action: :import}} = socket) do
    allow_upload(socket, :document,
      accept: ~w(.md .markdown .html .htm .txt),
      max_entries: 20,
      max_file_size: 5_000_000
    )
  end

  defp maybe_allow_import(socket), do: socket

  # ---- Step navigation ----

  @impl true
  def handle_event("choose_format", %{"format" => fmt}, socket) when fmt in ~w(markdown html) do
    if socket.assigns.post do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> update(:draft, &Map.put(&1, "format", fmt))
       |> assign(step: 2)}
    end
  end

  def handle_event("advance", _params, socket) do
    {:noreply, assign(socket, step: min(socket.assigns.step + 1, 3))}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: max(socket.assigns.step - 1, 1))}
  end

  # Stepper navigation — jump straight to a step by clicking it. Steps 2–3
  # require a chosen format; step 1 is always reachable. The draft is kept in
  # sync by each step's `phx-change="validate"`, so jumping never loses input.
  def handle_event("goto_step", %{"step" => step}, socket) do
    target = String.to_integer(step)
    format_chosen = socket.assigns.draft["format"] not in [nil, ""]

    if target == 1 or (target in 2..3 and format_chosen) do
      {:noreply, assign(socket, step: target)}
    else
      {:noreply, socket}
    end
  end

  # ---- Import ----

  # phx-change target for the upload form — entries validate client-side; we
  # just need a handler for LiveView to register them.
  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_import", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  def handle_event("import_file", _params, socket) do
    files =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    case files do
      [] ->
        {:noreply, socket}

      [{filename, body}] ->
        # A single file flows into the wizard so the title/slug can be
        # refined before saving — landing on step 2 (Details).
        draft = Map.merge(socket.assigns.draft, Content.Import.attrs_from_file(filename, body))

        {:noreply,
         socket
         |> assign(draft: draft, step: 2, slug_touched: false)
         |> assign_changeset(draft)}

      many ->
        # Multiple files are created as drafts straight away — there's no
        # single wizard to land on. The user refines them from the list.
        {ok, failed} =
          Enum.reduce(many, {0, 0}, fn {filename, body}, {ok, failed} ->
            attrs = Content.Import.attrs_from_file(filename, body)

            case Content.create_post(socket.assigns.site.id, attrs) do
              {:ok, _} -> {ok + 1, failed}
              {:error, _} -> {ok, failed + 1}
            end
          end)

        {:noreply,
         socket
         |> put_flash(:info, import_flash("post", ok, failed))
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/posts")}
    end
  end

  def handle_event("next_meta", %{"post" => params}, socket) do
    draft = Map.merge(socket.assigns.draft, params)
    changeset = build_changeset(socket, draft)

    if Ecto.Changeset.get_field(changeset, :title) not in [nil, ""] do
      {:noreply,
       socket
       |> assign(draft: draft, step: 3)
       |> assign_changeset(draft)}
    else
      {:noreply,
       socket
       |> assign(draft: draft, show_errors: true)
       |> assign_changeset(draft, validate: true)}
    end
  end

  def handle_event("toggle_tag", %{"id" => id}, socket) do
    selected = socket.assigns.draft["tag_ids"] || []

    selected =
      if id in selected, do: List.delete(selected, id), else: [id | selected]

    {:noreply, update(socket, :draft, &Map.put(&1, "tag_ids", selected))}
  end

  # ---- Validation / save ----

  def handle_event("validate", %{"post" => params} = full_params, socket) do
    target = List.last(full_params["_target"] || [])
    slug_touched = update_slug_touched(socket.assigns[:slug_touched], target, params)

    params =
      if !slug_touched and target == "title" do
        # Force ensure_slug to re-derive from the (just-changed) title by
        # blanking the slug. Otherwise the previous derived value sticks.
        Map.put(params, "slug", "")
      else
        params
      end

    draft = Map.merge(socket.assigns.draft, params)

    {:noreply,
     socket
     |> assign(draft: draft, slug_touched: slug_touched)
     |> assign_changeset(draft, validate: true)}
  end

  def handle_event("save", %{"post" => post_params} = params, socket) do
    # New posts use the explicit "draft" / "publish" action from one of two
    # buttons. Existing posts have a single "Save" button — preserve the
    # post's current published state (the page-head toggle changes that
    # independently).
    publish? =
      case socket.assigns.post do
        nil -> Map.get(params, "action", "draft") == "publish"
        post -> post.published
      end

    full_params =
      socket.assigns.draft
      |> Map.merge(post_params)
      |> Map.put("published", to_string(publish?))

    result =
      case socket.assigns.post do
        nil -> Content.create_post(socket.assigns.site.id, full_params)
        post -> Content.update_post(post, full_params)
      end

    case result do
      {:ok, post} ->
        flash =
          case {socket.assigns.post, publish?} do
            {nil, true} -> "Post published."
            {nil, false} -> "Draft saved."
            {_, _} -> "Changes saved."
          end

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/posts/#{post.id}/edit")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: :post),
           changeset: changeset,
           show_errors: true
         )}
    end
  end

  def handle_event("toggle_publish", _params, socket) do
    case socket.assigns[:post] do
      nil ->
        {:noreply, socket}

      post ->
        new_published = !post.published

        case Content.update_post(post, %{"published" => to_string(new_published)}) do
          {:ok, updated} ->
            msg = if new_published, do: "Post published.", else: "Post unpublished."

            {:noreply,
             socket
             |> assign(post: updated)
             |> update(:draft, &Map.put(&1, "published", to_string(new_published)))
             |> put_flash(:info, msg)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't update publish state.")}
        end
    end
  end

  def handle_event("delete", _params, socket) do
    case socket.assigns[:post] do
      nil ->
        {:noreply, socket}

      post ->
        {:ok, _} = Content.delete_post(post)

        {:noreply,
         socket
         |> put_flash(:info, "Post deleted.")
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/posts")}
    end
  end

  def handle_event("dismiss_external_change", _params, socket),
    do: {:noreply, assign(socket, external_change: nil)}

  # ---- Editor tools (sidebar) ----

  def handle_event("format_body", _params, socket) do
    format = socket.assigns.draft["format"] || "markdown"
    formatted = Masthead.Content.Format.run(socket.assigns.draft["body"] || "", format)
    draft = Map.put(socket.assigns.draft, "body", formatted)

    {:noreply,
     socket
     |> assign(draft: draft)
     |> assign_changeset(draft)
     |> push_event("editor_replace", %{id: "post-body-editor-" <> format, text: formatted})}
  end

  @impl true
  def handle_info({:file_picked, %Masthead.Uploads.Upload{} = upload, _ctx}, socket) do
    format = socket.assigns.draft["format"] || "markdown"
    text = image_snippet(upload, format)

    {:noreply,
     push_event(socket, "editor_insert", %{id: "post-body-editor-" <> format, text: text})}
  end

  def handle_info({:file_picked, _other, _ctx}, socket), do: {:noreply, socket}

  # Someone else changed or deleted the post being edited. The updated_at
  # compare filters out this editor's own save (whose @post already carries
  # the new timestamp).
  def handle_info({:realtime, :content, %{kind: :post, id: id} = meta}, socket) do
    {:noreply, note_external_change(socket, id, meta)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp note_external_change(socket, id, %{op: op, updated_at: updated_at}) do
    post = socket.assigns.post

    cond do
      is_nil(post) or post.id != id ->
        socket

      op == :deleted ->
        assign(socket, external_change: :deleted)

      op == :updated and updated_at != post.updated_at ->
        assign(socket, external_change: :updated)

      true ->
        socket
    end
  end

  defp image_snippet(upload, "html"),
    do: ~s(<img src="#{Masthead.Uploads.url(upload)}" alt="#{image_alt(upload)}" />)

  defp image_snippet(upload, _markdown),
    do: "![#{image_alt(upload)}](#{Masthead.Uploads.url(upload)})"

  defp image_alt(upload), do: upload.filename |> Path.rootname()

  # ---- Helpers ----

  defp update_slug_touched(_prev, "slug", %{"slug" => slug}) when slug != "", do: true
  defp update_slug_touched(_prev, "slug", _params), do: false
  defp update_slug_touched(prev, _target, _params), do: prev || false

  defp post_to_draft(post) do
    %{
      "title" => post.title,
      "slug" => post.slug,
      "excerpt" => post.excerpt,
      "format" => post.format,
      "body" => post.body,
      "published" => to_string(post.published),
      "tag_ids" => Enum.map(post.tags, &to_string(&1.id))
    }
  end

  defp import_flash(entity, ok, 0), do: "Imported #{ok} #{entity}s."

  defp import_flash(entity, ok, failed),
    do: "Imported #{ok} #{entity}s. #{failed} couldn't be imported."

  defp import_error(:too_large), do: "That file is too large (5MB max)."
  defp import_error(:not_accepted), do: "Only Markdown and HTML files are allowed."
  defp import_error(:too_many_files), do: "You can import up to 20 files at once."
  defp import_error(other), do: to_string(other)

  defp build_changeset(socket, attrs) do
    base = socket.assigns[:post] || %Post{site_id: socket.assigns.site.id}
    Content.change_post(base, attrs)
  end

  defp assign_changeset(socket, attrs, opts \\ []) do
    changeset = build_changeset(socket, attrs)

    changeset =
      if Keyword.get(opts, :validate, false),
        do: Map.put(changeset, :action, :validate),
        else: changeset

    assign(socket, form: to_form(changeset, as: :post), changeset: changeset)
  end

  # ---- Render ----

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@page_title}
      site={@site}
      current_user={@current_user}
      action_count={@action_count}
      present_users={@present_users}
      flash={@flash}
      active={:posts}
    >
      <:actions>
        <.publish_status :if={@post} published={@post.published} />
      </:actions>

      <.external_change_banner
        change={@external_change}
        reload_to={@post && ~p"/#{@site.slug}/posts/#{@post.id}/edit"}
      />

      <div class="wizard" id="post-wizard" phx-hook="SaveShortcut" data-save-param="post">
        <%= case @step do %>
          <% 0 -> %>
            <.import_step uploads={@uploads} site_slug={@site.slug} />
          <% 1 -> %>
            <.format_step
              locked={@post != nil}
              format={@draft["format"]}
              editing={@post != nil}
              site_slug={@site.slug}
            />
          <% 2 -> %>
            <.meta_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@post != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
              tags={@tags}
              selected_tag_ids={@draft["tag_ids"] || []}
            />
          <% 3 -> %>
            <.content_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@post != nil}
              published={@post != nil and @post.published}
              site={@site}
              view_path={@post && "/posts/" <> @post.slug}
              site_slug={@site.slug}
              show_errors={@show_errors}
            />
        <% end %>
      </div>
    </.shell>
    """
  end

  attr :step, :integer, default: 1

  defp stepper(assigns) do
    ~H"""
    <ol class="stepper">
      <li
        :for={i <- 1..3}
        class={"step " <> step_class(i, @step)}
        phx-click="goto_step"
        phx-value-step={i}
        role="button"
        tabindex="0"
      >
        <span class="step-num">{i}</span>
        <span class="step-label">{step_label(i)}</span>
      </li>
    </ol>
    """
  end

  defp step_class(i, current) when i < current, do: "step-done"
  defp step_class(i, current) when i == current, do: "step-current"
  defp step_class(_, _), do: "step-future"

  defp step_label(1), do: "Format"
  defp step_label(2), do: "Details"
  defp step_label(3), do: "Content"

  attr :uploads, :map, required: true
  attr :site_slug, :string, required: true

  defp import_step(assigns) do
    ~H"""
    <h2 class="wizard-heading">Import posts</h2>
    <p class="wizard-intro muted">
      Upload one or more Markdown (<code>.md</code>) or HTML (<code>.html</code>)
      files. The format is detected per file and the title is prefilled from the
      filename. YAML frontmatter is stripped — its <code>title</code>
      wins and <code>draft: false</code>
      publishes. Import a single file to refine it in
      the editor, or several to create them in bulk.
    </p>

    <form id="import-form" phx-submit="import_file" phx-change="validate_import" class="form">
      <label class="dropzone" phx-drop-target={@uploads.document.ref}>
        <.live_file_input upload={@uploads.document} />
        <p class="dropzone-headline">Drop files here, or click to browse</p>
        <p class="muted">Markdown or HTML, up to 5MB each.</p>
      </label>

      <ul :if={@uploads.document.entries != []} class="upload-entries">
        <li :for={entry <- @uploads.document.entries}>
          <span class="filename">{entry.client_name}</span>
          <button
            type="button"
            phx-click="cancel_import"
            phx-value-ref={entry.ref}
            class="btn btn-sm"
          >
            Remove
          </button>
          <p :for={err <- upload_errors(@uploads.document, entry)} class="error entry-error">
            {import_error(err)}
          </p>
        </li>
      </ul>

      <p :for={err <- upload_errors(@uploads.document)} class="error">{import_error(err)}</p>
    </form>

    <div class="wizard-footer">
      <.link navigate={~p"/#{@site_slug}/posts"} class="btn">Cancel</.link>
      <button
        type="submit"
        form="import-form"
        class="btn btn-primary"
        disabled={@uploads.document.entries == []}
      >
        Import &rarr;
      </button>
    </div>
    """
  end

  attr :locked, :boolean, default: false
  attr :format, :string, default: nil
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true

  defp format_step(assigns) do
    ~H"""
    <.stepper step={1} />

    <h2 class="wizard-heading">
      {if @editing, do: "Post format", else: "How do you want to write this post?"}
    </h2>

    <.format_cards selected={@format} locked={@locked} />

    <div :if={@locked} class="wizard-footer">
      <.link navigate={~p"/#{@site_slug}/posts"} class="btn">Cancel</.link>
      <span class="muted">Format is set at creation and cannot be changed.</span>
      <button type="button" phx-click="advance" class="btn btn-primary">Continue &rarr;</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :changeset, :map, required: true
  attr :format, :string, required: true
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true
  attr :show_errors, :boolean, default: false
  attr :tags, :list, default: []
  attr :selected_tag_ids, :list, default: []

  defp meta_step(assigns) do
    ~H"""
    <.stepper step={2} />

    <form id="meta-form" phx-submit="next_meta" phx-change="validate" class="form">
      <.error_list changeset={@changeset} show={@show_errors} />

      <label>
        Title <input type="text" name="post[title]" value={@form[:title].value} required autofocus />
      </label>

      <label>
        Slug
        <input type="text" name="post[slug]" value={@form[:slug].value} placeholder="auto from title" />
        <small>
          URL: <code>/posts/{Ecto.Changeset.get_field(@changeset, :slug) || "your-slug"}</code>
        </small>
      </label>

      <label>
        Excerpt <textarea
          name="post[excerpt]"
          rows="3"
          placeholder="One or two sentences shown on the homepage and in the &lt;meta&gt; description."
        >{@form[:excerpt].value}</textarea>
      </label>

      <div class="field">
        <span class="field-label">Tags</span>
        <div class="tag-picker">
          <button
            :for={t <- @tags}
            type="button"
            phx-click="toggle_tag"
            phx-value-id={t.id}
            class={["tag-toggle", to_string(t.id) in @selected_tag_ids && "tag-toggle-on"]}
          >
            {t.name}
          </button>
          <.link navigate={~p"/#{@site_slug}/settings"} class="tag-chip-add">Manage tags</.link>
        </div>
      </div>

      <input type="hidden" name="post[format]" value={@format} />
    </form>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
      <span class="muted">Writing in <strong>{format_label(@format)}</strong></span>
      <button type="submit" form="meta-form" class="btn btn-primary">Continue &rarr;</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :changeset, :map, required: true
  attr :format, :string, required: true
  attr :editing, :boolean, default: false
  attr :published, :boolean, default: false
  attr :site, :map, default: nil
  attr :view_path, :string, default: nil
  attr :site_slug, :string, required: true
  attr :show_errors, :boolean, default: false

  defp content_step(assigns) do
    ~H"""
    <.stepper step={3} />

    <div class="content-layout">
      <div class="content-main">
        <form id="content-form" phx-submit="save" phx-change="validate" class="form post-form">
          <.error_list changeset={@changeset} show={@show_errors} />

          <input type="hidden" name="post[title]" value={@form[:title].value} />
          <input type="hidden" name="post[slug]" value={@form[:slug].value} />
          <input type="hidden" name="post[excerpt]" value={@form[:excerpt].value} />
          <input type="hidden" name="post[format]" value={@format} />

          <.body_editor form={@form} format={@format} />
        </form>
      </div>

      <.content_sidebar
        editing={@editing}
        published={@published}
        entity="post"
        site={@site}
        view_path={@view_path}
        format={@format}
      />
    </div>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :format, :string, required: true

  defp body_editor(assigns) do
    ~H"""
    <div class="editor">
      <div class="editor-pane">
        <label for="post-body-textarea" class="editor-label">Body ({format_label(@format)})</label>
        <div
          id={"post-body-editor-" <> @format}
          class="code-editor"
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language={@format}
        >
          <textarea
            id="post-body-textarea"
            name="post[body]"
            rows="20"
            phx-debounce="200"
            class="markdown-editor"
          >{@form[:body].value}</textarea>
        </div>
      </div>
    </div>
    """
  end

  defp format_label("html"), do: "HTML"
  defp format_label(_), do: "Markdown"
end
