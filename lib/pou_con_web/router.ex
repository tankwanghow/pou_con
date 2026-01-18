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

  # API pipeline for central monitoring system
  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_query_params)
  end

  # API authentication via API key
  pipeline :api_auth do
    plug(PouConWeb.Plugs.ApiAuth)
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

    cond do
      current_role == required_role ->
        conn

      current_role in [:admin, :user] ->
        # Logged in but wrong role - redirect to dashboard
        conn
        |> put_flash(:error, "Admin access required. Please log in with admin credentials.")
        |> redirect(to: "/")
        |> halt()

      true ->
        # Not logged in - redirect to login with return_to
        return_to = request_path_with_query(conn)

        conn
        |> put_flash(:error, "Please log in with admin credentials.")
        |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")
        |> halt()
    end
  end

  defp request_path_with_query(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> "#{conn.request_path}?#{qs}"
    end
  end

  # --------------------------------------------------------------------
  # API Routes (For Central Monitoring System)
  # Requires API key authentication via header or query param
  # --------------------------------------------------------------------
  scope "/api", PouConWeb.API do
    pipe_through([:api, :api_auth])

    # Real-time status
    get("/status", StatusController, :index)

    # House info
    get("/info", SyncController, :info)

    # Sync endpoints for data download
    get("/sync/counts", SyncController, :all_counts)
    get("/sync/equipment_events", SyncController, :equipment_events)
    get("/sync/sensor_snapshots", SyncController, :sensor_snapshots)
    get("/sync/water_meter_snapshots", SyncController, :water_meter_snapshots)
    get("/sync/power_meter_snapshots", SyncController, :power_meter_snapshots)
    get("/sync/daily_summaries", SyncController, :daily_summaries)
    get("/sync/flocks", SyncController, :flocks)
    get("/sync/flock_logs", SyncController, :flock_logs)
    get("/sync/task_categories", SyncController, :task_categories)
    get("/sync/task_templates", SyncController, :task_templates)
    get("/sync/task_completions", SyncController, :task_completions)
  end

  # --------------------------------------------------------------------
  # Public Routes (No Session Required)
  # Dashboard is the main entry point - no login required for viewing
  # Equipment index pages are public for monitoring (read-only view)
  # --------------------------------------------------------------------
  scope "/", PouConWeb do
    pipe_through(:browser)

    # Non-LiveView auth routes (outside live_session)
    get("/auth/session", SessionController, :create)
    post("/logout", AuthController, :logout)

    # Public LiveView routes with default hook for current_role assignment
    live_session :public,
      on_mount: [{PouConWeb.AuthHooks, :default}] do
      # Dashboard is now the root page - accessible without login
      live("/", Live.Dashboard.Index, :index)
      live("/dashboard", Live.Dashboard.Index, :index)

      # Auth routes
      live("/setup", Live.Auth.Setup, :index)
      live("/login", Live.Auth.Login, :index)

      # Reports are public (read-only)
      live("/reports", Live.Reports.Index, :index)

      # User guide / help
      live("/help", Live.Help.UserGuide, :index)

      # Equipment monitoring pages (public - users can view status)
      live("/temp_hum", Live.TempHum.Index, :index)
      live("/fans", Live.Fans.Index, :index)
      live("/pumps", Live.Pumps.Index, :index)
      live("/lighting", Live.Lighting.Index, :index)
      live("/sirens", Live.Sirens.Index, :index)
      live("/power_indicators", Live.PowerIndicators.Index, :index)
      live("/egg_collection", Live.EggCollection.Index, :index)
      live("/feed", Live.Feeding.Index, :index)
      live("/dung", Live.Dung.Index, :index)
      live("/power_meters", Live.PowerMeters.Index, :index)
      live("/water_meters", Live.WaterMeters.Index, :index)
    end
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
      live("/data_points", Live.Admin.DataPoints.Index, :index)
      live("/data_points/new", Live.Admin.DataPoints.Form, :new)
      live("/data_points/:id/edit", Live.Admin.DataPoints.Form, :edit)
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

      # Flock management (admin only)
      live("/flocks", Live.Admin.Flock.Index, :index)
      live("/flocks/new", Live.Admin.Flock.Form, :new)
      live("/flocks/:id/edit", Live.Admin.Flock.Form, :edit)

      # Alarm rules configuration (admin only)
      live("/alarm", Live.Admin.Alarm.Index, :index)
      live("/alarm/new", Live.Admin.Alarm.Form, :new)
      live("/alarm/:id/edit", Live.Admin.Alarm.Form, :edit)

      # Operations task templates (admin only)
      live("/tasks", Live.Admin.Tasks.Index, :index)
      live("/tasks/new", Live.Admin.Tasks.Form, :new)
      live("/tasks/:id/edit", Live.Admin.Tasks.Form, :edit)
    end
  end

  # --------------------------------------------------------------------
  # Authenticated Routes (Any logged-in user can access)
  # --------------------------------------------------------------------
  scope "/", PouConWeb do
    pipe_through([:browser, :authenticated])

    live_session :require_authenticated_user,
      on_mount: [{PouConWeb.AuthHooks, :ensure_authenticated}] do
      # Flock pages - accessible to any authenticated user
      live("/flock/:id/logs", Live.Flock.Logs, :index)
      live("/flock/:id/daily-yields", Live.Flock.DailyYields, :index)

      # Operations tasks - accessible to any authenticated user
      live("/operations/tasks", Live.Operations.Tasks, :index)
    end
  end
end
