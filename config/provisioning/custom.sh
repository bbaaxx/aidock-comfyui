#!/bin/bash

# Custom provisioning for bbaaxx/aidock-comfyui.
# Sourced by /opt/ai-dock/bin/init.sh during container init.
# Derived from config/provisioning/flux.sh (structure, token auth) and
# get-models-sd-official.sh (explicit filenames + existence checks).

# https://raw.githubusercontent.com/bbaaxx/aidock-comfyui/main/config/provisioning/custom.sh

# ============================================================
# CONFIG - edit this section only.
# Model entry format: "url|filename" or "url|filename|sha256"
# (filename/sha256 optional; sha256 verified when given).
# Files that already exist are skipped, so re-provisioning with a
# persistent disk is cheap.
# ============================================================

NODES=(
    # url@sha — pinned commits only (supply chain). To update: bump the SHA.
    "https://github.com/ltdrdata/ComfyUI-Manager@4f56cf3dfa7de5d8a8614dfe202ff8d613ba2244"
)

PIP_PACKAGES=(
    #"package-1"
)

APT_PACKAGES=(
    # multi-connection downloader: HF/CDN per-connection throttling makes
    # single-stream wget crawl (~2MB/s vs ~300MB/s with aria2 -x16)
    "aria2"
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

# Clone custom nodes if missing (pinned "url@sha"); install requirements
# on first provision only. Pre-existing dirs are left untouched: re-running
# pip against volume content on every boot would let volume tampering
# become boot-time code execution.
function provisioning_get_nodes() {
    for entry in "${NODES[@]}"; do
        [[ -z $entry ]] && continue
        repo="${entry%@*}"
        sha=""
        [[ $entry == *"@"* ]] && sha="${entry##*@}"
        dir="${repo##*/}"
        path="/opt/ComfyUI/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            printf "Node already present: %s (skipping)\n" "${dir}"
            continue
        fi
        printf "Cloning node: %s...\n" "${repo}"
        git clone "${repo}" "${path}" --recursive
        if [[ -n $sha ]]; then
            ( cd "$path" && git checkout --detach "${sha}" && git submodule update --init --recursive )
        fi
        [[ -e $requirements ]] && "$COMFYUI_VENV_PIP" install --no-cache-dir -r "${requirements}"
    done
}

# $1 target dir, remaining args: "url|filename" or "url|filename|sha256"
# entries. Skips any file that already exists and is non-empty; when a
# sha256 is given it is verified after download (and for skipped files).
function provisioning_get_models() {
    dir="$1"
    shift
    entries=("$@")
    [[ -z ${entries[0]} ]] && return 0
    mkdir -p "$dir"
    for entry in "${entries[@]}"; do
        [[ -z $entry ]] && continue
        IFS='|' read -r url file sha256 <<< "${entry}"
        if [[ -z $file ]]; then
            file="${url%%\?*}"; file="${file##*/}"
        fi
        target="${dir}/${file}"
        if [[ -s $target ]]; then
            printf "Skipping (exists): %s\n" "${file}"
        else
            printf "Downloading: %s -> %s\n" "${url}" "${target}"
            provisioning_download "${url}" "${target}"
        fi
        if [[ -n $sha256 ]]; then
            if [[ $(sha256sum "${target}" | cut -d' ' -f1) != "${sha256}" ]]; then
                printf "ERROR: sha256 mismatch for %s - refusing to keep file\n" "${file}" >&2
                rm -f "${target}"
                return 1
            fi
            printf "sha256 OK: %s\n" "${file}"
        fi
    done
}

# Auth header for known gated hosts; aria2 (multi-connection) preferred,
# wget fallback. Downloads to explicit target path, resumable.
function provisioning_download() {
    url="$1"; target="$2"
    auth_header=""
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header="Authorization: Bearer ${HF_TOKEN}"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_header="Authorization: Bearer ${CIVITAI_TOKEN}"
    fi
    dir="$(dirname "${target}")"; file="$(basename "${target}")"
    if command -v aria2c >/dev/null 2>&1; then
        aria2_args=(-c -x16 -s16 -q --file-allocation=none --summary-interval=30
                    -d "${dir}" -o "${file}")
        [[ -n $auth_header ]] && aria2_args+=(--header="${auth_header}")
        aria2c "${aria2_args[@]}" "${url}"
    else
        if [[ -n $auth_header ]]; then
            wget --header="${auth_header}" -q --show-progress -e dotbytes=4M -c -O "${target}" "${url}"
        else
            wget -q --show-progress -e dotbytes=4M -c -O "${target}" "${url}"
        fi
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
