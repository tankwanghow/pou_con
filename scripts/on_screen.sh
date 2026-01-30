#!/bin/bash
# Turn on the screen by setting backlight to max brightness
# Used by swayidle for screen resume

# Auto-detect backlight device
for bl in lcd_backlight 10-0045 rpi_backlight backlight; do
    if [ -f "/sys/class/backlight/$bl/brightness" ]; then
        MAX_BRIGHTNESS=$(cat "/sys/class/backlight/$bl/max_brightness" 2>/dev/null || echo "5")
        echo "$MAX_BRIGHTNESS" > "/sys/class/backlight/$bl/brightness"
        exit 0
    fi
done

echo "ERROR: No backlight device found" >&2
exit 1
