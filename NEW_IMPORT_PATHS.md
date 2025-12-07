# New Import Paths Quick Reference

Use this as a reference when writing new code or updating imports after migration.

## Core Contexts

### Authentication
```elixir
alias PouCon.Auth.Auth
alias PouCon.Auth.AppConfig
```

### Hardware Layer
```elixir
alias PouCon.Hardware.DeviceManager
alias PouCon.Hardware.PortSupervisor
alias PouCon.Hardware.Modbus.Adapter
alias PouCon.Hardware.Ports.Ports
alias PouCon.Hardware.Ports.Port
```

### Equipment
```elixir
# Context
alias PouCon.Equipment.Devices
alias PouCon.Equipment.EquipmentLoader

# Schemas
alias PouCon.Equipment.Schemas.Device
alias PouCon.Equipment.Schemas.Equipment
alias PouCon.Equipment.Schemas.VirtualDigitalState

# Controllers
alias PouCon.Equipment.Controllers.{
  Fan,
  Pump,
  Light,
  TempHumSen,
  Feeding,
  FeedIn,
  Egg,
  Dung,
  DungHor,
  DungExit,
  EnvironmentController
}
```

### Automation

#### Feeding
```elixir
alias PouCon.Automation.Feeding.FeedingSchedules
alias PouCon.Automation.Feeding.FeedingScheduler
alias PouCon.Automation.Feeding.Schemas.Schedule
```

#### Lighting
```elixir
alias PouCon.Automation.Lighting.LightSchedules
alias PouCon.Automation.Lighting.LightScheduler
alias PouCon.Automation.Lighting.Schemas.Schedule
```

#### Egg Collection
```elixir
alias PouCon.Automation.EggCollection.EggCollectionSchedules
alias PouCon.Automation.EggCollection.EggCollectionScheduler
alias PouCon.Automation.EggCollection.Schemas.Schedule
```

#### Environment
```elixir
alias PouCon.Automation.Environment.EnvironmentControl
alias PouCon.Automation.Environment.Schemas.Config
```

### Utilities
```elixir
alias PouCon.Utils.Timezones
alias PouCon.Utils.Modbus
```

## Web Layer

### Components - Equipment
```elixir
alias PouConWeb.Components.Equipment.{
  FanComponent,
  PumpComponent,
  LightComponent,
  TempHumComponent,
  FeedingComponent,
  FeedInComponent,
  EggComponent,
  DungComponent,
  DungHorComponent,
  DungExitComponent
}
```

### Components - Summaries
```elixir
alias PouConWeb.Components.Summaries.{
  FanSummaryComponent,
  PumpSummaryComponent,
  LightSummaryComponent,
  TempHumSummaryComponent,
  FeedingSummaryComponent,
  EggSummaryComponent,
  DungSummaryComponent
}
```

### LiveViews - Auth
```elixir
alias PouConWeb.Live.Auth.{Login, Setup, AdminSettings}
```

### LiveViews - Admin
```elixir
alias PouConWeb.Live.Admin.Devices.{Index, Form}
alias PouConWeb.Live.Admin.Ports.{Index, Form}
alias PouConWeb.Live.Admin.Equipment.{Index, Form}
```

### LiveViews - Features
```elixir
alias PouConWeb.Live.Dashboard.Index
alias PouConWeb.Live.Feeding.{Index, Schedules}
alias PouConWeb.Live.Lighting.Schedules
alias PouConWeb.Live.EggCollection.Schedules
alias PouConWeb.Live.Environment.{Index, Control}
alias PouConWeb.Live.Dung.Index
```

## Router Paths

```elixir
# Public
live "/", LandingLive.Index
live "/login", Live.Auth.Login
live "/setup", Live.Auth.Setup

# Authenticated
live "/dashboard", Live.Dashboard.Index
live "/simulation", SimulationLive
live "/environment", Live.Environment.Index
live "/environment/control", Live.Environment.Control
live "/egg_collection", Live.EggCollection.Schedules
live "/light_schedule", Live.Lighting.Schedules
live "/feeding_schedule", Live.Feeding.Schedules
live "/dung", Live.Dung.Index
live "/feed", Live.Feeding.Index

# Admin
live "/admin/settings", Live.Auth.AdminSettings
live "/admin/devices", Live.Admin.Devices.Index
live "/admin/ports", Live.Admin.Ports.Index
live "/admin/equipment", Live.Admin.Equipment.Index
```

## Common Patterns

### Using Equipment Controllers in LiveViews
```elixir
defmodule PouConWeb.Live.Dashboard.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Controllers.{
    Fan,
    Pump,
    TempHumSen,
    Feeding,
    Egg,
    Dung,
    Light,
    FeedIn
  }

  alias PouCon.Equipment.Devices
  alias PouCon.Hardware.DeviceManager
end
```

### Using Schedulers
```elixir
defmodule PouConWeb.Live.Feeding.Schedules do
  use PouConWeb, :live_view

  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Automation.Feeding.Schemas.Schedule
  alias PouCon.Equipment.Controllers.{Feeding, FeedIn}
  alias PouCon.Equipment.Devices
end
```

### Using Components
```elixir
defmodule PouConWeb.Live.Dashboard.Index do
  # In render function
  <.live_component
    module={PouConWeb.Components.Equipment.FanComponent}
    id={eq.name}
    equipment={eq}
  />

  <.live_component
    module={PouConWeb.Components.Summaries.FanSummaryComponent}
    id="fan_summ"
    equipments={fans}
  />
end
```

## File Locations

### Core Contexts
- Auth: `lib/pou_con/auth/`
- Hardware: `lib/pou_con/hardware/`
- Equipment: `lib/pou_con/equipment/`
- Automation: `lib/pou_con/automation/{feeding,lighting,egg_collection,environment}/`
- Utils: `lib/pou_con/utils/`

### Web
- Components: `lib/pou_con_web/components/{equipment,summaries}/`
- LiveViews: `lib/pou_con_web/live/{auth,dashboard,admin,feeding,lighting,environment,egg_collection,dung}/`
- Plugs: `lib/pou_con_web/plugs/`

## Migration Checklist

When writing new code or refactoring:

- [ ] Use full module paths (don't assume old locations)
- [ ] Group related aliases together
- [ ] Use multi-alias syntax for related modules
- [ ] Check this reference guide for correct paths
- [ ] Update imports if you see deprecation warnings
