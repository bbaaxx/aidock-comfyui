#!/bin/bash

# Custom provisioning for bbaaxx/aidock-comfyui.
# Sourced by /opt/ai-dock/bin/init.sh during container init.
# Derived from config/provisioning/flux.sh (structure, token auth) and
# get-models-sd-official.sh (explicit filenames + existence checks).

# https://raw.githubusercontent.com/bbaaxx/aidock-comfyui/main/config/provisioning/custom.sh

# ============================================================
# CONFIG - edit this section only.
# Model entry format: "url|filename"  (filename optional if the
# URL path already ends with it). Files that already exist are
# skipped, so re-provisioning with a persistent disk is cheap.
# ============================================================

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
)

PIP_PACKAGES=(
    #"package-1"
)

APT_PACKAGES=(
    #"package-1"
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/cyberdelia/CyberRealisticPony/resolve/main/CyberRealisticPony_V18.0_F16.safetensors?download=true|CyberRealisticPony_V18.0_F16.safetensors"
)

UNET_MODELS=(
    # FLUX unets / diffusion models go here -> models/unet
)

CLIP_MODELS=(
    # t5xxl, clip_l, etc -> models/clip
)

VAE_MODELS=(
    # -> models/vae
)

LORA_MODELS=(
    # -> models/lora
)

CONTROLNET_MODELS=(
    # -> models/controlnet
)

ESRGAN_MODELS=(
    # upscalers -> models/esrgan
)

EMBEDDINGS=(
    # textual inversion -> models/embeddings
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

STORAGE="${WORKSPACE}/storage/stable_diffusion/models"

function provisioning_start() {
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh comfyui

    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_models "${STORAGE}/ckpt"       "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models "${STORAGE}/unet"       "${UNET_MODELS[@]}"
    provisioning_get_models "${STORAGE}/clip"       "${CLIP_MODELS[@]}"
    provisioning_get_models "${STORAGE}/vae"        "${VAE_MODELS[@]}"
    provisioning_get_models "${STORAGE}/lora"       "${LORA_MODELS[@]}"
    provisioning_get_models "${STORAGE}/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_models "${STORAGE}/esrgan"     "${ESRGAN_MODELS[@]}"
    provisioning_get_models "${STORAGE}/embeddings" "${EMBEDDINGS[@]}"
    provisioning_link_storage
    provisioning_restart_services
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    [[ -n $APT_PACKAGES ]] && sudo $APT_INSTALL ${APT_PACKAGES[@]}
}

function provisioning_get_pip_packages() {
    [[ -n $PIP_PACKAGES ]] && "$COMFYUI_VENV_PIP" install --no-cache-dir ${PIP_PACKAGES[@]}
}

# Clone custom nodes if missing; install their python requirements.
function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        [[ -z $repo ]] && continue
        dir="${repo##*/}"
        path="/opt/ComfyUI/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            printf "Node already present: %s\n" "${dir}"
        else
            printf "Cloning node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
        fi
        [[ -e $requirements ]] && "$COMFYUI_VENV_PIP" install --no-cache-dir -r "${requirements}"
    done
}

# $1 target dir, remaining args: "url|filename" entries.
# Skips any file that already exists and is non-empty.
function provisioning_get_models() {
    dir="$1"
    shift
    entries=("$@")
    [[ -z ${entries[0]} ]] && return 0
    mkdir -p "$dir"
    for entry in "${entries[@]}"; do
        [[ -z $entry ]] && continue
        url="${entry%%|*}"
        if [[ $entry == *"|"* ]]; then
            file="${entry##*|}"
        else
            file="${url%%\?*}"; file="${file##*/}"
        fi
        target="${dir}/${file}"
        if [[ -s $target ]]; then
            printf "Skipping (exists): %s\n" "${file}"
            continue
        fi
        printf "Downloading: %s -> %s\n" "${url}" "${target}"
        provisioning_download "${url}" "${target}"
    done
}

# Auth header for known gated hosts; wget to explicit target path.
function provisioning_download() {
    url="$1"; target="$2"
    auth_token=""
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer ${auth_token}" -q --show-progress -e dotbytes=4M -O "${target}" "${url}"
    else
        wget -q --show-progress -e dotbytes=4M -O "${target}" "${url}"
    fi
}

# storage-monitor's inotify watches may not be established when downloads
# land; create the storage -> /opt/ComfyUI/models symlinks explicitly.
function provisioning_link_storage() {
    find "${WORKSPACE}/storage" -exec \
        bash /opt/ai-dock/storage_monitor/bin/manage-symlinks.sh \
        "${WORKSPACE}/storage" {} \;
}

# ComfyUI caches its model list at startup and may already be running.
function provisioning_restart_services() {
    supervisorctl restart comfyui comfyui_api_wrapper || true
}

function provisioning_print_header() {
    printf "\n##############################################\n#          Provisioning container            #\n#         This will take some time           #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

provisioning_start
