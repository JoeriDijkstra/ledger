defmodule Masthead.AccountsDisableTest do
  use Masthead.DataCase

  alias Masthead.Accounts
  alias Masthead.Accounts.User
  alias Masthead.Sites

  setup do
    Masthead.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "dis-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    # Verified so the disable cascade (which only fires on losing a *verified*
    # member) takes the owner's solo site offline.
    {:ok, user} = Accounts.confirm_user(Accounts.generate_email_token(user, "confirm"))

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "dis#{System.unique_integer([:positive])}",
        "name" => "Disable Test",
        "owner_id" => user.id
      })

    %{user: user, site: site}
  end

  test "disable_user stamps the user, cascades to sites, revokes tokens",
       %{user: user, site: site} do
    token = Accounts.generate_email_token(user, "confirm")

    assert {:ok, disabled} = Accounts.disable_user(user)
    assert User.disabled?(disabled)

    # site no longer resolves publicly -> Subdomain plug will 404
    refute Sites.get_site_by_slug(site.slug)

    # tokens revoked
    assert :error = Accounts.confirm_user(token)
  end

  test "disable_user is idempotent", %{user: user} do
    assert {:ok, _} = Accounts.disable_user(user)
    assert {:ok, _} = Accounts.disable_user(Repo.reload(user))
  end

  test "enable_user restores the account and its sites", %{user: user, site: site} do
    {:ok, user} = Accounts.disable_user(user)
    refute Sites.get_site_by_slug(site.slug)

    assert {:ok, enabled} = Accounts.enable_user(user)
    refute User.disabled?(enabled)
    assert Sites.get_site_by_slug(site.slug)
  end

  test "a disabled custom domain stops resolving and drops from the allow-list",
       %{user: user, site: site} do
    Repo.update_all(
      from(s in Masthead.Sites.Site, where: s.id == ^site.id),
      set: [custom_domain: "example.test", custom_domain_status: "active"]
    )

    assert Sites.get_site_by_custom_domain("example.test")
    assert "example.test" in Sites.list_active_custom_domains()

    {:ok, _} = Accounts.disable_user(user)

    refute Sites.get_site_by_custom_domain("example.test")
    refute "example.test" in Sites.list_active_custom_domains()
  end
end
