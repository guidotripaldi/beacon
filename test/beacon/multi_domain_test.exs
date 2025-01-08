
defmodule Beacon.MultiDomainTest.DomainReachableRouter do
  use Beacon.BeaconTest.Web, :router
  use Beacon.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope path: "/host_test", host: "host.com" do
    pipe_through :browser
    beacon_site "/", site: :host_test
  end

  scope path: "/other" do
    pipe_through :browser
  end

  scope path: "/", host: "example1.com" do
    pipe_through :browser
    beacon_site "/", site: :domain_1_test
  end

  scope path: "/", host: "example2.com" do
    pipe_through :browser
    beacon_site "/", site: :domain_2_test
  end

  scope path: "/" do
    pipe_through :browser
    beacon_site "/", site: :my_site
  end
end

defmodule Beacon.MultiDomainTest.DomainNotReachableRouter do
  use Beacon.BeaconTest.Web, :router
  use Beacon.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope path: "/host_test", host: "host.com" do
    pipe_through :browser
    beacon_site "/", site: :host_test
  end

  scope path: "/other" do
    pipe_through :browser
  end

  scope path: "/" do
    pipe_through :browser
    beacon_site "/", site: :my_site
  end

  scope path: "/", host: "example1.com" do
    pipe_through :browser
    beacon_site "/", site: :domain_1_test
  end

  scope path: "/", host: "example2.com" do
    pipe_through :browser
    beacon_site "/", site: :domain_2_test
  end
end

defmodule Beacon.MultiDomainTest do
  use ExUnit.Case, async: true
  use Beacon.Test
  alias Beacon.Router
  alias Beacon.Config

  describe "multidomain" do
    defp config(site, opts \\ []) do
      Map.merge(
        Config.fetch!(site),
        # Enum.into(opts, %{router: Beacon.BeaconTest.ReachTestRouter})
        Enum.into(opts, %{router: Beacon.MultiDomainTest.DomainReachableRouter })
      )
    end

    test "match domains" do
      config = config(:domain_1_test, site_domain: "example1.com")
      assert Router.reachable?(config, prefix: "/")

      config = config(:domain_2_test, site_domain: "example2.com")
      assert Router.reachable?(config, prefix: "/")

    end

    test "not match domains" do
      config = config(:domain_1_test, site_domain: "example1.com", router: Beacon.MultiDomainTest.DomainNotReachableRouter)
      refute Router.reachable?(config, prefix: "/")

      config = config(:domain_2_test, site_domain: "example2.com", router: Beacon.MultiDomainTest.DomainNotReachableRouter)
      refute Router.reachable?(config, prefix: "/")

      config = config(:domain_2_test, site_domain: "example3.com", router: Beacon.MultiDomainTest.DomainReachableRouter)
      refute Router.reachable?(config, prefix: "/")
    end
  end

end



