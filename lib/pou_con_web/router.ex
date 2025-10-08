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
    live("/dashboard", DashboardLive.Index, :index)
    # Add more protected routes here
    live("/slave_id_changer", SlaveIdChangerLive, :index)
  end
end
