alias Masthead.Accounts
alias Masthead.Sites
alias Masthead.Content

# Demo user (a platform admin, so the admin overview is reachable in dev)
{:ok, user} =
  case Accounts.get_user_by_email("admin@example.com") do
    nil -> Accounts.register_user(%{"email" => "admin@example.com", "password" => "password1234"})
    existing -> {:ok, existing}
  end

{:ok, user} = Accounts.set_admin(user, true)

# Demo site ("admin" is a reserved slug now — it routes to the admin overview)
{:ok, site} =
  case Sites.get_site_by_slug("demo") do
    nil ->
      Sites.create_site(
        %{
          "slug" => "demo",
          "name" => "Example Site",
          "title" => "Example Site",
          "description" =>
            "A placeholder site seeded with Masthead. Use it to explore the platform — edit, publish, or delete anything."
        },
        user
      )

    existing ->
      {:ok, existing}
  end

# Sample posts (only if site has no posts yet)
case Content.list_posts(site.id) do
  [] ->
    posts = [
      %{
        "title" => "Welcome to your new site",
        "excerpt" => "A short tour of what Masthead lets you publish and how to get started.",
        "body" => """
        ## Welcome

        This is the first post on your new Masthead site. You can edit it,
        unpublish it, or delete it from the admin dashboard.

        ### What you can publish

        - **Posts** — dated entries that show up in the post list. Best for
          articles, updates, and announcements.
        - **Pages** — evergreen content like *About* or *Contact* that
          appears in the site navigation.
        - **Blog pages** — a page that renders the post list. Set it as the
          homepage to make your post archive the front door of the site.

        ### Where to go next

        Open the admin dashboard, switch to the **Posts** tab, and write
        your first piece. You can use Markdown or paste raw HTML — both
        are sanitized before they reach your readers.
        """,
        "published" => true
      },
      %{
        "title" => "Writing in Markdown",
        "excerpt" =>
          "Markdown gives you headings, lists, links, and code without leaving the keyboard.",
        "body" => """
        Markdown is a plain-text shorthand for the common structural
        elements of writing online. Masthead uses it as the default editor
        because it gets out of the way.

        ### What you get for free

        - Headings via `#`, `##`, `###`
        - **Bold** with `**bold**` and *italic* with `*italic*`
        - Lists, both bulleted and 1. numbered
        - Inline `code` and fenced code blocks
        - Links like [this one](https://example.com)
        - Block quotes and horizontal rules

        > Markdown was designed to read naturally as plain text — even
        > without a renderer in front of it.

        If you need anything Markdown can't express — tables with custom
        classes, embedded video, complex layouts — switch the post format
        to **HTML** when you create it. The output is sanitized either way.
        """,
        "published" => true
      },
      %{
        "title" => "Draft: not visible yet",
        "excerpt" => "Drafts are hidden from public listings until you publish them.",
        "body" =>
          "This post is a draft. It doesn't appear on the public site until you publish it from the admin dashboard.",
        "published" => false
      }
    ]

    for attrs <- posts do
      {:ok, _} = Content.create_post(site.id, attrs)
    end

    {:ok, _about} =
      Content.create_page(site.id, %{
        "title" => "About",
        "slug" => "about",
        "body" => """
        ## About this site

        This is the placeholder *About* page for the example site seeded
        with Masthead. Edit the body, change the slug, or delete it — it's
        here to show that a published page appears automatically in the
        site navigation.
        """,
        "published" => true
      })

  _ ->
    IO.puts("Site already has posts; skipping seed content.")
end

IO.puts("""

Seeded:
  user:  admin@example.com / password1234 (platform admin)
  site:  http://demo.lvh.me:4000
  admin: http://localhost:4000/admin
""")
