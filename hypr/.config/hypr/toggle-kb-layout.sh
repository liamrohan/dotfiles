#!/bin/bash

current_layout=$(hyprctl -j devices | jq -r '.keyboards[0].active_keymap')

if [[ "$current_layout" == "English (US)" ]]; then
  hyprctl keyword input:kb_layout gb
else
  hyprctl keyword input:kb_layout us
fi
