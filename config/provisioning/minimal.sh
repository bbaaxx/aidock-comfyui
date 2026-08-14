#!/bin/bash

# Bare-minimum provisioning: one SD1.5 checkpoint so ComfyUI generates
# out of the box. Sourced by /opt/ai-dock/bin/init.sh before services
# start. Extend from default.sh if you need more.

# https://raw.githubusercontent.com/bbaaxx/aidock-comfyui/main/config/provisioning/minimal.sh

source /opt/ai-dock/etc/environment.sh

MODEL_DIR="${WORKSPACE}/storage/stable_diffusion/models/ckpt"
mkdir -p "${MODEL_DIR}"

# -nc: skip if already present (idempotent across pod restarts)
wget -qnc --show-progress -P "${MODEL_DIR}" \
    "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
