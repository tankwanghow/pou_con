defmodule PouConWeb.Router do
  use PouConWeb, :router

  # --------------------------------------------------------------------
  # Pipelines
  # --------------------------------------------------------------------
  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PouConWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  # HTTP-level auth (initial request only)
  pipeline :authenticated do
    plug(PouConWeb.Plugs.Auth)
  end

  pipeline :required_admin do
    plug(:authenticate_role, :admin)
  end

  # --------------------------------------------------------------------
  # Role Check Plug (HTTP only)
  # --------------------------------------------------------------------
  defp authenticate_role(conn, required_role) do
    current_role = get_session(conn, :current_role)

    if current_role == required_role do
      conn
    else
      conn
      |> put_flash(:error, "Access denied. Please log in with the correct credentials.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  # --------------------------------------------------------------------
  # Public Routes (No Session)
  # --------------------------------------------------------------------
  scope "/", PouConWeb do
    pipe_through(:browser)

    live("/", LandingLive.Index, :index)
    live("/setup", AuthLive.Setup, :index)
    live("/login", AuthLive.Login, :index)

    get("/auth/session", SessionController, :create)
    post("/logout", AuthController, :logout)
  end

  # --------------------------------------------------------------------
  # Authenticated Session (Admin + User)
  # Hooks run on every mount (including live navigation)
  # --------------------------------------------------------------------
  scope "/", PouConWeb do
    pipe_through([:browser, :authenticated])

    live_session :ensure_authenticated,
      on_mount: [{PouConWeb.AuthHooks, :ensure_authenticated}] do
      live("/dashboard", DashboardLive, :index)
      live("/simulation", SimulationLive, :index)
      live("/environment", EnvironmentLive, :index)
      live("/environment/control", EnvironmentControlLive, :index)
      live("/egg_collection", EggCollectionLive, :index)
      live("/light_schedule", LightScheduleLive, :index)
      live("/dung", DungLive, :index)
      live("/feed", FeedLive, :index)
    end
  end

  # --------------------------------------------------------------------
  # Admin-Only Session
  # Separate session forces full reload when crossing boundary
  # --------------------------------------------------------------------

  scope "/admin", PouConWeb do
    pipe_through([:browser, :required_admin])

    live_session :ensure_is_admin,
      on_mount: [
        # {PouConWeb.AuthHooks, :ensure_authenticated},
        {PouConWeb.AuthHooks, :ensure_is_admin}
      ] do
      live("/settings", AuthLive.AdminSettings)
      live("/devices", DeviceLive.Index, :index)
      live("/ports", PortLive.Index, :index)
      live("/equipment", EquipmentLive.Index, :index)
      live("/devices/new", DeviceLive.Form, :new)
      live("/devices/:id/edit", DeviceLive.Form, :edit)
      live("/ports/new", PortLive.Form, :new)
      live("/ports/:id/edit", PortLive.Form, :edit)
      live("/equipment/new", EquipmentLive.Form, :new)
      live("/equipment/:id/edit", EquipmentLive.Form, :edit)
    end
  end
end
