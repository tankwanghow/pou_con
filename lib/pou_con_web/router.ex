defmodule PouConWeb.Router do
  use PouConWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PouConWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :authenticated do
    plug(PouConWeb.Plugs.Auth)
  end

  scope "/auth", PouConWeb do
    pipe_through(:browser)

    get("/session", SessionController, :create)
  end

  scope "/", PouConWeb do
    pipe_through(:browser)

    # Public routes
    live("/", LandingLive.Index, :index)
    live("/login", AuthLive.Login, :index)
    live("/setup", AuthLive.Setup, :index)

    # Logout route
    post("/logout", AuthController, :logout)
  end

  scope "/app", PouConWeb do
    pipe_through([:browser, :authenticated])

    # Protected routes
    live("/dashboard", DashboardLive)
    # Add more protected routes here
    live("/setup_device", SetupDeviceLive)

    live "/devices", DeviceLive.Index, :index
    live "/devices/new", DeviceLive.Form, :new
    live "/devices/:id/edit", DeviceLive.Form, :edit

    live "/ports", PortLive.Index, :index
    live "/ports/new", PortLive.Form, :new
    live "/ports/:id/edit", PortLive.Form, :edit
  end
end
