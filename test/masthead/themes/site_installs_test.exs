defmodule Masthead.Themes.SiteInstallsTest do
  use Masthead.DataCase, async: true

  alias Masthead.{Accounts, Sites, Themes}

  setup do
    Themes.Seed.run()
    %{owner: register("owner"), other: register("other")}
  end

  defp register(prefix) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    user
  end

  defp upload(user, name) do
    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: name,
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    theme
  end

  defp published(user, name) do
    {:ok, theme} = Themes.publish_theme(upload(user, name))
    theme
  end

  defp site_for(user) do
    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "s#{System.unique_integer([:positive])}",
        "name" => "S",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    site
  end

  describe "only default remains a built-in" do
    test "studio and tailwind are gone; default is present" do
      assert Themes.get_built_in_by_slug("default")
      refute Themes.get_built_in_by_slug("studio")
      refute Themes.get_built_in_by_slug("tailwind")
      assert "default" in Enum.map(Themes.list_built_ins(), & &1.slug)
    end
  end

  describe "install_theme/2" do
    test "installs a published theme onto a site", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = published(other, "Pub")
      assert {:ok, _} = Themes.install_theme(site, theme)
      assert MapSet.member?(Themes.installed_theme_ids(site.id), theme.id)
    end

    test "site owner may install their own unpublished theme", %{owner: owner} do
      site = site_for(owner)
      theme = upload(owner, "Mine")
      assert {:ok, _} = Themes.install_theme(site, theme)
    end

    test "another user's unpublished theme is rejected", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = upload(other, "Draft")
      assert {:error, :not_installable} = Themes.install_theme(site, theme)
    end

    test "is idempotent", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = published(other, "Pub")
      {:ok, _} = Themes.install_theme(site, theme)
      {:ok, _} = Themes.install_theme(site, theme)
      assert MapSet.size(Themes.installed_theme_ids(site.id)) == 1
    end
  end

  describe "uninstall_theme/2" do
    test "removes an installed theme", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = published(other, "Pub")
      {:ok, _} = Themes.install_theme(site, theme)

      assert {:ok, _} = Themes.uninstall_theme(site, theme.id)
      refute MapSet.member?(Themes.installed_theme_ids(site.id), theme.id)
    end

    test "refuses to uninstall the site's active theme", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = published(other, "Active")
      {:ok, _} = Themes.install_theme(site, theme)
      {:ok, site} = Sites.update_settings(site, %{"theme_id" => theme.id})

      assert {:error, :in_use} = Themes.uninstall_theme(site, theme.id)
    end
  end

  describe "list_themes_for_site/1" do
    test "is Default plus the site's installed themes", %{owner: owner, other: other} do
      site = site_for(owner)
      theme = published(other, "Installed One")

      before = Themes.list_themes_for_site(site) |> Enum.map(& &1.slug)
      assert "default" in before
      refute theme.id in (Themes.list_themes_for_site(site) |> Enum.map(& &1.id))

      {:ok, _} = Themes.install_theme(site, theme)
      assert theme.id in (Themes.list_themes_for_site(site) |> Enum.map(& &1.id))
    end
  end
end
