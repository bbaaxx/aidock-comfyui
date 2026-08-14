#!/bin/bash

# Bare-minimum provisioning: one SD1.5 checkpoint so ComfyUI generates
# out of the box. Sourced by /opt/ai-dock/bin/init.sh during container
# init. Extend from default.sh if you need more.

# https://raw.githubusercontent.com/bbaaxx/aidock-comfyui/main/config/provisioning/minimal.sh

source /opt/ai-dock/etc/environment.sh

MODEL_DIR="${WORKSPACE}/storage/stable_diffusion/models/ckpt"
mkdir -p "${MODEL_DIR}"

# -nc: skip if already present (idempotent across pod restarts)
wget -qnc --show-progress -P "${MODEL_DIR}" \
    "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"

# storage-monitor links storage files into /opt/ComfyUI/models via inotify,
# but its watches may not be established before the download lands (event
# lost -> no symlink). Create links explicitly for all storage files.
find "${WORKSPACE}/storage" -exec \
    bash /opt/ai-dock/storage_monitor/bin/manage-symlinks.sh \
    "${WORKSPACE}/storage" {} \;

# ComfyUI caches its model list at startup and supervisord may already
# have started it while the download was running.
supervisorctl restart comfyui comfyui_api_wrapper || true
