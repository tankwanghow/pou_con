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
    live("/setup", Live.Auth.Setup, :index)
    live("/login", Live.Auth.Login, :index)

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
      live("/dashboard", Live.Dashboard.Index, :index)
      live("/simulation", SimulationLive, :index)
      live("/environment", Live.Environment.Index, :index)
      live("/environment/control", Live.Environment.Control, :index)
      live("/lighting", Live.Lighting.Index, :index)
      live("/lighting/schedules", Live.Lighting.Schedules, :index)
      live("/egg_collection", Live.EggCollection.Index, :index)
      live("/egg_collection/schedules", Live.EggCollection.Schedules, :index)
      live("/feeding_schedule", Live.Feeding.Schedules, :index)
      live("/dung", Live.Dung.Index, :index)
      live("/feed", Live.Feeding.Index, :index)
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
      live("/settings", Live.Auth.AdminSettings)
      live("/devices", Live.Admin.Devices.Index, :index)
      live("/ports", Live.Admin.Ports.Index, :index)
      live("/equipment", Live.Admin.Equipment.Index, :index)
      live("/interlock", Live.Admin.Interlock.Index, :index)
      live("/devices/new", Live.Admin.Devices.Form, :new)
      live("/devices/:id/edit", Live.Admin.Devices.Form, :edit)
      live("/ports/new", Live.Admin.Ports.Form, :new)
      live("/ports/:id/edit", Live.Admin.Ports.Form, :edit)
      live("/equipment/new", Live.Admin.Equipment.Form, :new)
      live("/equipment/:id/edit", Live.Admin.Equipment.Form, :edit)
      live("/interlock/new", Live.Admin.Interlock.Form, :new)
      live("/interlock/:id/edit", Live.Admin.Interlock.Form, :edit)
    end
  end
end
