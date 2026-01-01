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
  # Public Routes (No Session Required)
  # Dashboard is the main entry point - no login required for viewing
  # Equipment index pages are public for monitoring (read-only view)
  # --------------------------------------------------------------------
  scope "/", PouConWeb do
    pipe_through(:browser)

    # Dashboard is now the root page - accessible without login
    live("/", Live.Dashboard.Index, :index)
    live("/dashboard", Live.Dashboard.Index, :index)

    # Auth routes
    live("/setup", Live.Auth.Setup, :index)
    live("/login", Live.Auth.Login, :index)
    get("/auth/session", SessionController, :create)
    post("/logout", AuthController, :logout)

    # Reports are public (read-only)
    live("/reports", Live.Reports.Index, :index)

    # Equipment monitoring pages (public - users can view status)
    live("/environment", Live.Environment.Index, :index)
    live("/lighting", Live.Lighting.Index, :index)
    live("/egg_collection", Live.EggCollection.Index, :index)
    live("/feed", Live.Feeding.Index, :index)
    live("/dung", Live.Dung.Index, :index)
  end

  # --------------------------------------------------------------------
  # Admin-Only Session
  # All settings, schedules, and control pages require admin login
  # --------------------------------------------------------------------
  scope "/admin", PouConWeb do
    pipe_through([:browser, :required_admin])

    live_session :ensure_is_admin,
      on_mount: [
        {PouConWeb.AuthHooks, :ensure_is_admin},
        {PouConWeb.AuthHooks, :check_system_time}
      ] do
      # Admin settings
      live("/settings", Live.Auth.AdminSettings)
      live("/system_time", Live.Admin.SystemTime.Index, :index)

      # Hardware configuration
      live("/devices", Live.Admin.Devices.Index, :index)
      live("/devices/new", Live.Admin.Devices.Form, :new)
      live("/devices/:id/edit", Live.Admin.Devices.Form, :edit)
      live("/ports", Live.Admin.Ports.Index, :index)
      live("/ports/new", Live.Admin.Ports.Form, :new)
      live("/ports/:id/edit", Live.Admin.Ports.Form, :edit)
      live("/equipment", Live.Admin.Equipment.Index, :index)
      live("/equipment/new", Live.Admin.Equipment.Form, :new)
      live("/equipment/:id/edit", Live.Admin.Equipment.Form, :edit)
      live("/interlock", Live.Admin.Interlock.Index, :index)
      live("/interlock/new", Live.Admin.Interlock.Form, :new)
      live("/interlock/:id/edit", Live.Admin.Interlock.Form, :edit)

      # Simulation (dev only)
      live("/simulation", SimulationLive, :index)

      # Environment control configuration (admin only)
      live("/environment/control", Live.Environment.Control, :index)

      # Lighting schedules (admin only)
      live("/lighting/schedules", Live.Lighting.Schedules, :index)

      # Egg collection schedules (admin only)
      live("/egg_collection/schedules", Live.EggCollection.Schedules, :index)

      # Feeding schedules (admin only)
      live("/feeding_schedule", Live.Feeding.Schedules, :index)
    end
  end
end
