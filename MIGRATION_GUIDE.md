# PouCon Directory Restructure Migration Guide

This guide will help you migrate your codebase to the new, cleaner directory structure.

## Overview

The new structure organizes code by domain and separates concerns more clearly:

- **`hardware/`** - Low-level hardware communication (Modbus, ports, device manager)
- **`equipment/`** - Equipment schemas and controllers
- **`automation/`** - All scheduling organized by subdomain (feeding, lighting, eggs, environment)
- **`auth/`** - Authentication consolidated
- **`utils/`** - Shared utilities

Web layer is also better organized with equipment and summary components grouped, and LiveViews organized by feature.

## Prerequisites

**IMPORTANT: Create a backup first!**

```bash
cd /home/tankwanghow/Projects/elixir/pou_con
git add -A
git commit -m "Backup before directory restructure"
# Or create a branch
git checkout -b backup-before-restructure
git checkout -b directory-restructure
```

## Migration Steps

### Step 1: Review the Migration Plan

Review the proposed directory structure in the scripts:
- `migrate_structure.sh` - File movement script
- `update_modules.exs` - Module name and import updater

### Step 2: Run the Migration

Execute the migration in the correct order:

```bash
# Make scripts executable
chmod +x migrate_structure.sh
chmod +x update_modules.exs

# 1. Move files to new locations
./migrate_structure.sh

# 2. Update module names and imports
./update_modules.exs

# 3. Try to compile
mix compile
```

### Step 3: Fix Any Remaining Issues

The automated scripts handle most cases, but you may need to manually fix:

1. **Router paths** - Update LiveView module paths in `lib/pou_con_web/router.ex`
2. **Application supervision tree** - Update module names in `lib/pou_con/application.ex`
3. **Test files** - Update module references in tests
4. **Config files** - Update any module references in `config/`

### Step 4: Run Tests

```bash
mix test
```

### Step 5: Clean Up Empty Directories

```bash
# Remove any empty old directories
find lib -type d -empty -delete
```

## Common Issues and Fixes

### Issue 1: Compilation Errors

**Problem**: `module not found` or `undefined function`

**Solution**: Check that:
1. The file was moved correctly
2. The module name was updated in the file
3. All references were updated (especially in `application.ex` and `router.ex`)

### Issue 2: LiveView Not Found

**Problem**: LiveView routes return 404

**Solution**: Update the router paths:

```elixir
# Old
live("/dashboard", DashboardLive, :index)

# New
live("/dashboard", Live.Dashboard.Index, :index)
```

### Issue 3: Component Not Rendering

**Problem**: Component not found errors

**Solution**: Update the alias in the LiveView:

```elixir
# Old
alias PouConWeb.Components.FanComponent

# New
alias PouConWeb.Components.Equipment.FanComponent
```

## Manual Updates Required

### 1. Router (`lib/pou_con_web/router.ex`)

Update all LiveView references:

```elixir
# Auth
live("/login", Live.Auth.Login, :index)
live("/setup", Live.Auth.Setup, :index)

# Dashboard
live("/dashboard", Live.Dashboard.Index, :index)

# Admin
live("/admin/devices", Live.Admin.Devices.Index, :index)
live("/admin/ports", Live.Admin.Ports.Index, :index)
live("/admin/equipment", Live.Admin.Equipment.Index, :index)

# Features
live("/feeding_schedule", Live.Feeding.Schedules, :index)
live("/light_schedule", Live.Lighting.Schedules, :index)
live("/egg_collection", Live.EggCollection.Schedules, :index)
live("/environment", Live.Environment.Index, :index)
live("/environment/control", Live.Environment.Control, :index)
```

### 2. Application (`lib/pou_con/application.ex`)

Update supervision tree:

```elixir
children = [
  PouCon.Repo,
  PouConWeb.Telemetry,
  {Phoenix.PubSub, name: PouCon.PubSub},

  # Hardware layer
  PouCon.Hardware.PortSupervisor,
  PouCon.Hardware.DeviceManager,

  # Equipment
  PouCon.Equipment.DeviceControllerSupervisor,
  PouCon.Equipment.EquipmentLoader,

  # Automation
  PouCon.Automation.Feeding.FeedingScheduler,
  PouCon.Automation.Lighting.LightScheduler,
  PouCon.Automation.EggCollection.EggCollectionScheduler,
  PouCon.Automation.Environment.EnvironmentControl,

  PouConWeb.Endpoint
]
```

## Rollback

If something goes wrong:

```bash
git checkout backup-before-restructure
# Or
git reset --hard HEAD~1
```

## Benefits of New Structure

✅ **Clear separation of concerns** - Hardware, Equipment, Automation, Web
✅ **Better scalability** - Easy to add new equipment types or schedules
✅ **Easier navigation** - Related files are grouped together
✅ **Consistent naming** - No more `_live` suffixes in directories
✅ **Domain-driven design** - Code organized by business domain

## After Migration Checklist

- [ ] All files moved successfully
- [ ] `mix compile` succeeds without warnings
- [ ] `mix test` passes
- [ ] Router loads all LiveViews correctly
- [ ] Application starts without errors
- [ ] All pages load in the browser
- [ ] Empty directories cleaned up
- [ ] Git commit with the changes

## Need Help?

If you encounter issues:
1. Check the compilation errors carefully
2. Review the module mapping in `update_modules.exs`
3. Manually search for old module references: `rg "PouCon\.DeviceControllers"`
4. Use the rollback if needed and review the scripts
