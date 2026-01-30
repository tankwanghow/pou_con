#!/bin/bash
# Turn off the screen by setting backlight to 0
# Used by swayidle for screen blanking

# Auto-detect backlight device
for bl in lcd_backlight 10-0045 rpi_backlight backlight; do
    if [ -f "/sys/class/backlight/$bl/brightness" ]; then
        echo 0 > "/sys/class/backlight/$bl/brightness"
        exit 0
    fi
done

echo "ERROR: No backlight device found" >&2
exit 1
