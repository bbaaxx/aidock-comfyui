#!/bin/false

# This file will be sourced in init.sh (before services start).
#
# Applies COMFYUI_MANAGER_SECURITY_LEVEL to ComfyUI-Manager at boot.
# The image ships security_level=strong (see COPY_ROOT_99 pre-seed).
# Strong blocks installing custom nodes from the Manager UI; operators who
# need that can deploy with e.g. COMFYUI_MANAGER_SECURITY_LEVEL=weak and
# SHOULD revert to strong (or unset) after installing - weak permits
# arbitrary third-party code execution via the Manager API.

function preflight_manager_security() {
    level="${COMFYUI_MANAGER_SECURITY_LEVEL:-strong}"
    case "${level,,}" in
        strong|middle|normal|weak) level="${level,,}" ;;
        *) printf "Ignoring invalid COMFYUI_MANAGER_SECURITY_LEVEL=%s\n" "${level}"; return 0 ;;
    esac
    for cfg in \
        /opt/ComfyUI/user/__manager/config.ini \
        /opt/ComfyUI/user/_manager/config.ini \
        /opt/ComfyUI/user/default/ComfyUI-Manager/config.ini; do
        if [[ -f $cfg ]]; then
            sed -i "s/^security_level = .*/security_level = ${level}/" "${cfg}"
            printf "ComfyUI-Manager security_level=%s (%s)\n" "${level}" "${cfg}"
        fi
    done
}

preflight_manager_security
