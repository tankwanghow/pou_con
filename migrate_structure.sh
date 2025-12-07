#!/bin/bash
set -e

echo "========================================="
echo "PouCon Directory Restructure Migration"
echo "========================================="
echo ""
echo "This script will:"
echo "1. Move files to new directory structure"
echo "2. Update module names"
echo "3. Update all imports/aliases"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

cd /home/tankwanghow/Projects/elixir/pou_con

# ============================================
# 1. MOVE AUTH FILES
# ============================================
echo "Moving auth files..."
mv lib/pou_con/auth.ex lib/pou_con/auth/auth.ex

# ============================================
# 2. MOVE HARDWARE LAYER FILES
# ============================================
echo "Moving hardware layer files..."
mv lib/pou_con/device_manager.ex lib/pou_con/hardware/
mv lib/pou_con/device_manager_behaviour.ex lib/pou_con/hardware/
mv lib/pou_con/device_tree_parser.ex lib/pou_con/hardware/
mv lib/pou_con/port_supervisor.ex lib/pou_con/hardware/

# Move modbus
mv lib/pou_con/modbus/* lib/pou_con/hardware/modbus/
rmdir lib/pou_con/modbus

# Move ports
mv lib/pou_con/ports.ex lib/pou_con/hardware/ports/
mv lib/pou_con/ports/port.ex lib/pou_con/hardware/ports/
rmdir lib/pou_con/ports

# ============================================
# 3. MOVE EQUIPMENT FILES
# ============================================
echo "Moving equipment files..."
mv lib/pou_con/equipment_loader.ex lib/pou_con/equipment/
mv lib/pou_con/device_controller_supervisor.ex lib/pou_con/equipment/
mv lib/pou_con/devices.ex lib/pou_con/equipment/

# Move schemas
mv lib/pou_con/devices/device.ex lib/pou_con/equipment/schemas/
mv lib/pou_con/devices/equipment.ex lib/pou_con/equipment/schemas/
mv lib/pou_con/devices/virtual_digital_state.ex lib/pou_con/equipment/schemas/
rmdir lib/pou_con/devices

# Move controllers
mv lib/pou_con/device_controllers/* lib/pou_con/equipment/controllers/
rmdir lib/pou_con/device_controllers

# ============================================
# 4. MOVE AUTOMATION FILES
# ============================================
echo "Moving automation files..."

# Feeding
mv lib/pou_con/feeding_schedules.ex lib/pou_con/automation/feeding/
mv lib/pou_con/feeding_scheduler.ex lib/pou_con/automation/feeding/
mv lib/pou_con/feeding_schedules/schedule.ex lib/pou_con/automation/feeding/schemas/
rmdir lib/pou_con/feeding_schedules

# Lighting
mv lib/pou_con/light_schedules.ex lib/pou_con/automation/lighting/
mv lib/pou_con/light_scheduler.ex lib/pou_con/automation/lighting/
mv lib/pou_con/light_schedules/schedule.ex lib/pou_con/automation/lighting/schemas/
rmdir lib/pou_con/light_schedules

# Egg Collection
mv lib/pou_con/egg_collection_schedules.ex lib/pou_con/automation/egg_collection/
mv lib/pou_con/egg_collection_scheduler.ex lib/pou_con/automation/egg_collection/
mv lib/pou_con/egg_collection_schedules/schedule.ex lib/pou_con/automation/egg_collection/schemas/
rmdir lib/pou_con/egg_collection_schedules

# Environment
mv lib/pou_con/environment_control.ex lib/pou_con/automation/environment/
mv lib/pou_con/environment_control/config.ex lib/pou_con/automation/environment/schemas/
rmdir lib/pou_con/environment_control

# ============================================
# 5. MOVE UTILS
# ============================================
echo "Moving utilities..."
mv lib/pou_con/timezones.ex lib/pou_con/utils/
mv lib/pou_con/modbus.ex lib/pou_con/utils/ 2>/dev/null || true

# ============================================
# 6. MOVE WEB COMPONENTS
# ============================================
echo "Moving web components..."

# Equipment components
mv lib/pou_con_web/components/fan_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/pump_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/light_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/temp_hum_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/feeding_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/feed_in_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/egg_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/dung_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/dung_hor_component.ex lib/pou_con_web/components/equipment/
mv lib/pou_con_web/components/dung_exit_component.ex lib/pou_con_web/components/equipment/

# Summary components
mv lib/pou_con_web/components/fan_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/pump_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/light_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/temp_hum_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/feeding_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/egg_summary_component.ex lib/pou_con_web/components/summaries/
mv lib/pou_con_web/components/dung_summary_component.ex lib/pou_con_web/components/summaries/

# ============================================
# 7. MOVE LIVEVIEWS
# ============================================
echo "Moving LiveViews..."

# Auth
mv lib/pou_con_web/live/auth_live/login.ex lib/pou_con_web/live/auth/
mv lib/pou_con_web/live/auth_live/setup.ex lib/pou_con_web/live/auth/
mv lib/pou_con_web/live/auth_live/admin_settings.ex lib/pou_con_web/live/auth/
rmdir lib/pou_con_web/live/auth_live

# Dashboard
mv lib/pou_con_web/live/dashboard_live/index.ex lib/pou_con_web/live/dashboard/
rmdir lib/pou_con_web/live/dashboard_live

# Admin - Devices
mv lib/pou_con_web/live/device_live/index.ex lib/pou_con_web/live/admin/devices/
mv lib/pou_con_web/live/device_live/form.ex lib/pou_con_web/live/admin/devices/
rmdir lib/pou_con_web/live/device_live

# Admin - Ports
mv lib/pou_con_web/live/port_live/index.ex lib/pou_con_web/live/admin/ports/
mv lib/pou_con_web/live/port_live/form.ex lib/pou_con_web/live/admin/ports/
rmdir lib/pou_con_web/live/port_live

# Admin - Equipment
mv lib/pou_con_web/live/equipment_live/index.ex lib/pou_con_web/live/admin/equipment/
mv lib/pou_con_web/live/equipment_live/form.ex lib/pou_con_web/live/admin/equipment/
rmdir lib/pou_con_web/live/equipment_live

# Feeding
mv lib/pou_con_web/live/feed_live/index.ex lib/pou_con_web/live/feeding/
mv lib/pou_con_web/live/feed_live/feeding_schedule_live.ex lib/pou_con_web/live/feeding/schedules.ex
rmdir lib/pou_con_web/live/feed_live

# Lighting
mv lib/pou_con_web/live/light_schedule_live/index.ex lib/pou_con_web/live/lighting/schedules.ex
rmdir lib/pou_con_web/live/light_schedule_live

# Egg Collection
mv lib/pou_con_web/live/egg_collection_live/index.ex lib/pou_con_web/live/egg_collection/schedules.ex
rmdir lib/pou_con_web/live/egg_collection_live

# Environment
mv lib/pou_con_web/live/environment_live/index.ex lib/pou_con_web/live/environment/
mv lib/pou_con_web/live/environment_live/environment_control_live.ex lib/pou_con_web/live/environment/control.ex
rmdir lib/pou_con_web/live/environment_live

# Dung
mv lib/pou_con_web/live/dung_live/index.ex lib/pou_con_web/live/dung/
rmdir lib/pou_con_web/live/dung_live

# Plugs
mv lib/pou_con_web/plug/auth.ex lib/pou_con_web/plugs/
rmdir lib/pou_con_web/plug

echo ""
echo "========================================="
echo "Files moved successfully!"
echo "========================================="
echo ""
echo "Next step: Run the module update script to fix imports/aliases"
echo "Run: ./update_modules.exs"
