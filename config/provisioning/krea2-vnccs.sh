#!/bin/bash

# Krea 2 + VNCCS provisioning for bbaaxx/aidock-comfyui.
# Extends krea2.sh with the VNCCS node/model set measured on pod
# 5ecm567legsv8c (2026-09-01, snapshot delta spec in project wiki:
# reference/vnccs-provisioning-delta).
# Sourced by /opt/ai-dock/bin/init.sh during container init.
#
# Needs the cu128/cu130 images (v0.33.1+). Total footprint ~52GB models:
# use a >=150GB workspace volume. All model URLs public (no tokens).
#
# https://raw.githubusercontent.com/bbaaxx/aidock-comfyui/main/config/provisioning/krea2-vnccs.sh

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
    "https://github.com/Gourieff/ComfyUI-ReActor@6ad6b35a4df250d14cb2abf0808c9ffedf59f747"
    # VNCCS set (pinned to the install window verified working 2026-09-01)
    "https://github.com/AHEKOT/ComfyUI_VNCCS@2206d1743f7920a7b9a21f80f03777d9ddce74c3"
    "https://github.com/AHEKOT/ComfyUI_VNCCS_Utils@0a36e05a1db5fd10241e0a079565de0fc0513e14"
    "https://github.com/yolain/ComfyUI-Easy-Sam3@88fe578a1a5e03d95281197303d5d3a73fd5a089"
    "https://github.com/city96/ComfyUI-GGUF@6ea2651e7df66d7585f6ffee804b20e92fb38b8a"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack@429d0159ad429e64d2b3916e6e7be9c22d025c3c"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack@50c7b71a6a224734cc9b21963c6d1926816a97f1"
)

PIP_PACKAGES=(
    # ReActor runtime deps (its install.py is never run by provisioning).
    "onnxruntime-gpu"
    # VNCCS delta (pip freeze diff baseline->after-vnccs). Most arrive via
    # node requirements.txt; pinned here for the ones that didn't declare.
    "decord==0.6.0"
    "diskcache==5.6.3"
    "ftfy==6.1.1"
    "gguf==0.19.0"
    "hydra-core==1.3.6"
    "iopath==0.1.10"
    "json_repair==0.63.4"
    "lightning-utilities==0.15.3"
    "omegaconf==2.3.1"
    "piexif==1.1.3"
    "portalocker==4.3.0"
    "pycocotools==2.0.11"
    "pytorch-lightning==2.6.5"
    "roma==1.6.1"
    "torchmetrics==1.9.0"
    "yacs==0.1.8"
    "antlr4-python3-runtime==4.9.3"
    "dill==0.4.1"
)

APT_PACKAGES=(
    # multi-connection downloader: HF/CDN per-connection throttling makes
    # single-stream wget crawl (~2MB/s vs ~300MB/s with aria2 -x16)
    "aria2"
)

# llama_cpp_python: PyPI ships source-only (cmake build = minutes at boot).
# abetlen's cu124 wheel is prebuilt manylinux and bundles its own CUDA
# libs, so it works under the cu128 torch stack.
PIP_PACKAGES_EXTRA_INDEX=(
    "llama_cpp_python==0.3.35|https://abetlen.github.io/llama-cpp-python/whl/cu124"
)

CHECKPOINT_MODELS=(
    # Krea 2 is not a checkpoint - see DIFFUSION_MODELS below
    # VNCCS Illustrious checkpoint goes via VNCCS_DIRECT (nested subdir).
)

# Optional extra checkpoints at deploy time. Env EXTRA_CHECKPOINTS: JSON
# array of strings, each one of:
#   "https://huggingface.co/<repo>/resolve/main/<file>"   (direct)
#   "https://civitai.com/models/<id>"  or bare "<id>"     (civitai, needs
#                                                          CIVITAI_TOKEN for
#                                                          gated models)
#   "https://civitai.com/api/download/models/<id>"
# Filenames: HF from URL path; civitai from content-disposition.
# Lands in storage ckpt dir -> symlinked into models/checkpoints.
# Example: EXTRA_CHECKPOINTS='["https://huggingface.co/stabilityai/sdxl...","133005"]'

UNET_MODELS=(
    # legacy unet dir -> models/unet. NOTE: the VNCCS Q8 GGUF goes to
    # ComfyUI/models/unet directly (GGUF loader), see VNCCS_DIRECT below.
)

DIFFUSION_MODELS=(
    # krea2 turbo fp8 NOT provisioned here: the krea2 checkpoint in use is
    # darkBeast KREA2 FP8 (civitai 3078453), delivered by the template's
    # CUSTOM_PROVISION_B64 hook. Saves 13GB. Re-add if you want stock krea2:
    #"https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors|krea2_turbo_fp8_scaled.safetensors"
)

CLIP_MODELS=(
    # legacy clip dir (t5xxl, clip_l) -> models/clip
)

TEXT_ENCODERS=(
    # qwen3vl 4b fp8 (~5.2GB) -> models/text_encoders (krea2 base)
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors|qwen3vl_4b_fp8_scaled.safetensors"
)

VAE_MODELS=(
    # qwen image vae (~254MB) -> models/vae (shared krea2 + QIE2511)
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors|qwen_image_vae.safetensors"
)

LORA_MODELS=(
    # darkbrush style lora (~469MB) -> models/loras
    "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_darkbrush.safetensors|krea2_darkbrush.safetensors"
)

CONTROLNET_MODELS=(
    # -> models/controlnet
)

ESRGAN_MODELS=(
    # upscalers -> models/esrgan. APISR goes via VNCCS_DIRECT (it lives in
    # models/upscale_models, not the storage esrgan mapping).
)

INSIGHTFACE_MODELS=(
    # ReActor swapper -> models/insightface
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx|inswapper_128.onnx"
)

EMBEDDINGS=(
    # textual inversion -> models/embeddings
)

# VNCCS models land directly in ComfyUI/models subdirs (nested paths the
# storage->models symlink mapping doesn't cover). Format: "url|relpath"
# where relpath is relative to ${WORKSPACE}/ComfyUI/models.
VNCCS_DIRECT=(
    # Q8 GGUF diffusion model (~21.8GB) -> models/unet (ComfyUI-GGUF loader)
    "https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF/resolve/main/qwen-image-edit-2511-Q8_0.gguf|unet/qwen-image-edit-2511-Q8_0.gguf"
    # QIE2511 text encoder (~9.4GB)
    "https://huggingface.co/f5aiteam/CLIP/resolve/main/qwen_2.5_vl_7b_fp8_scaled.safetensors|text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
    # VNCCS LoRAs
    "https://huggingface.co/MIUProject/VNCCS_PoseStudio/resolve/main/models/loras/qwen/VNCCS/VNCCS_QIE2511_PoseStudio_ART_V5.9.5.safetensors|loras/qwen/VNCCS/VNCCS_QIE2511_PoseStudio_ART_V5.9.5.safetensors"
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/loras/qwen/VNCCS/VNCCS_QIE2511_ClothesCore-RC3.7.safetensors|loras/qwen/VNCCS/VNCCS_QIE2511_ClothesCore-RC3.7.safetensors"
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/loras/qwen/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors|loras/qwen/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"
    # upscaler
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/upscale_models/4x_APISR_GRL_GAN_generator.pth|upscale_models/4x_APISR_GRL_GAN_generator.pth"
    # support models (ReActor/Impact/Easy-Sam3 auto-downloaders would fetch
    # these lazily; provision explicitly for deterministic boot)
    "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth|sams/sam_vit_b_01ec64.pth"
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt|ultralytics/bbox/face_yolov8m.pt"
    "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8s.pt|ultralytics/bbox/hand_yolov8s.pt"
    "https://huggingface.co/Bingsu/adetailer/resolve/main/person_yolov8m-seg.pt|ultralytics/segm/person_yolov8m-seg.pt"
    "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.3.pth|facerestore_models/GFPGANv1.3.pth"
    "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.4/GFPGANv1.4.pth|facerestore_models/GFPGANv1.4.pth"
    "https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth|facerestore_models/codeformer-v0.1.0.pth"
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GPEN-BFR-512.onnx|facerestore_models/GPEN-BFR-512.onnx"
    # Illustrious pipeline (VNCCS character steps 1-3): suggested ckpt +
    # turbo (DMD2) + age helper (Mimimeter) LoRAs
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/checkpoints/Illustrious/ILFlatMix.safetensors|checkpoints/Illustrious/ILFlatMix.safetensors"
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/loras/DMD2/dmd2_sdxl_4step_lora_fp16.safetensors|loras/DMD2/dmd2_sdxl_4step_lora_fp16.safetensors"
    "https://huggingface.co/MIUProject/VNCCS_v3.0/resolve/main/models/loras/IL/mimimeter.safetensors|loras/IL/mimimeter.safetensors"
    # SeedVR2 upscaler (VNCCS character_generator), pinned repo revision
    # (matches SEEDVR_HF_REVISION in ComfyUI_VNCCS @2206d174)
    "https://huggingface.co/Comfy-Org/SeedVR2/resolve/a457bf495efbd40ea92f699f7d2b5d2febeca176/diffusion_models/seedvr2_7b_sharp_fp16.safetensors|diffusion_models/seedvr2_7b_sharp_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/SeedVR2/resolve/a457bf495efbd40ea92f699f7d2b5d2febeca176/vae/ema_vae_fp16.safetensors|vae/ema_vae_fp16.safetensors"
    # Character Wizard LLM (llama.cpp), pinned to QWEN_VL_MODEL_REVISION in
    # ComfyUI_VNCCS @2206d174
    "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/68bb8bc4b7df5289c143aaec0ab477a7d4051aab/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf|LLM/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
    "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/68bb8bc4b7df5289c143aaec0ab477a7d4051aab/mmproj-F16.gguf|LLM/mmproj-F16.gguf"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

STORAGE="${WORKSPACE}/storage/stable_diffusion/models"

function provisioning_start() {
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh comfyui

    provisioning_print_header
    provisioning_get_apt_packages
    # extra-index wheels BEFORE nodes: ComfyUI_VNCCS/requirements.txt pulls
    # llama-cpp-python from PyPI (source-only there -> CPU-only build ->
    # 7B LLM on 37 vCPUs hangs the box). Preinstalling the cu124 wheel
    # makes requirements.txt see it satisfied.
    provisioning_get_pip_packages_extra_index
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_models "${STORAGE}/ckpt"             "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models "${STORAGE}/unet"             "${UNET_MODELS[@]}"
    provisioning_get_models "${STORAGE}/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_models "${STORAGE}/clip"             "${CLIP_MODELS[@]}"
    provisioning_get_models "${STORAGE}/text_encoders"    "${TEXT_ENCODERS[@]}"
    provisioning_get_models "${STORAGE}/vae"        "${VAE_MODELS[@]}"
    provisioning_get_models "${STORAGE}/lora"       "${LORA_MODELS[@]}"
    provisioning_get_models "${STORAGE}/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_models "${STORAGE}/esrgan"     "${ESRGAN_MODELS[@]}"
    provisioning_get_models "${STORAGE}/insightface" "${INSIGHTFACE_MODELS[@]}"
    provisioning_get_models "${STORAGE}/embeddings" "${EMBEDDINGS[@]}"
    provisioning_get_vnccs_direct
    provisioning_get_extra_checkpoints
    provisioning_ld_library_path
    provisioning_patch_vnccs_proxy
    provisioning_link_storage
    provisioning_custom_hook
    provisioning_restart_services
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    [[ -n $APT_PACKAGES ]] && sudo $APT_INSTALL ${APT_PACKAGES[@]}
}

function provisioning_get_pip_packages() {
    [[ -n $PIP_PACKAGES ]] && "$COMFYUI_VENV_PIP" install --no-cache-dir ${PIP_PACKAGES[@]}
}

# entries "pkg==ver|extra-index-url" — wheels not on PyPI.
function provisioning_get_pip_packages_extra_index() {
    for entry in "${PIP_PACKAGES_EXTRA_INDEX[@]}"; do
        [[ -z $entry ]] && continue
        IFS='|' read -r pkg index <<< "${entry}"
        printf "Installing (extra-index %s): %s\n" "${index}" "${pkg}"
        "$COMFYUI_VENV_PIP" install --no-cache-dir --extra-index-url "${index}" "${pkg}"
    done
}

# Clone custom nodes if missing (pinned "url@sha"); install requirements
# on first provision only.
# NODES_PINNED=true (default): checkout the pinned @sha; existing dirs are
#   left untouched (volume tamper must not become boot-time code exec).
# NODES_PINNED=false: track latest default branch (clone HEAD; existing
#   dirs get git pull + requirements reinstall). Mutable supply chain -
#   use only when you actively want newest node code.
function provisioning_get_nodes() {
    pinned="${NODES_PINNED:-true}"
    for entry in "${NODES[@]}"; do
        [[ -z $entry ]] && continue
        repo="${entry%@*}"
        sha=""
        [[ $entry == *"@"* ]] && sha="${entry##*@}"
        dir="${repo##*/}"
        path="/opt/ComfyUI/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${pinned,,} == "false" ]]; then
                printf "Updating node (NODES_PINNED=false): %s...\n" "${dir}"
                ( cd "$path" && git pull )
                [[ -e $requirements ]] && "$COMFYUI_VENV_PIP" install --no-cache-dir -r "${requirements}"
            else
                printf "Node already present: %s (skipping)\n" "${dir}"
            fi
            continue
        fi
        printf "Cloning node: %s...\n" "${repo}"
        git clone "${repo}" "${path}" --recursive
        if [[ ${pinned,,} != "false" && -n $sha ]]; then
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

# VNCCS direct-to-target downloads: "url|relpath" under ComfyUI/models.
# Skips the HF-cache double-write VNCCS's own UI downloader causes
# (hf_hub_download cache + copy = 2x disk, filled an 80G volume once).
function provisioning_get_vnccs_direct() {
    base="${WORKSPACE}/ComfyUI/models"
    [[ -z ${VNCCS_DIRECT[0]} ]] && return 0
    for entry in "${VNCCS_DIRECT[@]}"; do
        [[ -z $entry ]] && continue
        IFS='|' read -r url rel <<< "${entry}"
        target="${base}/${rel}"
        if [[ -s $target ]]; then
            printf "Skipping (exists): %s\n" "${rel}"
            continue
        fi
        mkdir -p "$(dirname "${target}")"
        printf "Downloading: %s -> %s\n" "${url}" "${target}"
        provisioning_download "${url}" "${target}"
    done
}

# EXTRA_CHECKPOINTS: JSON array of URLs / civitai model ids (see CONFIG).
# Civitai entries resolve their filename from content-disposition; the
# civitai-fetch.sh pattern (skip when already present).
function provisioning_get_extra_checkpoints() {
    [[ -z ${EXTRA_CHECKPOINTS:-} ]] && return 0
    dir="${STORAGE}/ckpt"
    mkdir -p "$dir"
    printf "%s" "${EXTRA_CHECKPOINTS}" | python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
    assert isinstance(items, list)
except Exception:
    sys.exit("ERROR: EXTRA_CHECKPOINTS must be a JSON array of strings")
for it in items:
    print(it)
' | while read -r entry; do
        url="$entry"
        if [[ $url =~ ^[0-9]+$ ]]; then
            url="https://civitai.com/api/download/models/${url}"
        elif [[ $url =~ ^https?://(www\.)?civitai\.(com|red)/models/([0-9]+) ]]; then
            url="https://civitai.com/api/download/models/${BASH_REMATCH[3]}"
        fi
        if [[ $url =~ civitai\.(com|red) ]]; then
            # token as query param (both civitai hosts); append with & if the
            # URL already has a query string
            if [[ -n $CIVITAI_TOKEN && $url != *token=* ]]; then
                sep="?"; [[ $url == *\?* ]] && sep="&"
                url="${url}${sep}token=${CIVITAI_TOKEN}"
            fi
            # Filename: civitai 307-redirects to R2 with the real name in the
            # response-content-disposition query param. Do NOT follow the
            # redirect (-L): the R2 presigned URL 403s on HEAD.
            loc=$(curl -sI "$url" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' | tail -1)
            file=$(python3 -c '
import sys, urllib.parse as up, re
loc = sys.argv[1] if len(sys.argv) > 1 else ""
m = re.search(r"filename%3D%22([^%\"]+)%22", loc) or re.search(r"filename=\\\"?([^&\";]+)", loc)
print(up.unquote(m.group(1)) if m else "")
' "$loc")
            if [[ -z $file ]]; then
                # fallback: content-disposition header (non-redirect case)
                file=$(curl -sIL "$url" | grep -i 'content-disposition' | tail -1 \
                    | sed -n 's/.*filename="\?\([^";]*\)"\?.*/\1/p' | tr -d '\r')
            fi
            [[ -z $file ]] && { printf "ERROR: no filename for %s (gated? token?)\n" "$url" >&2; continue; }
            target="${dir}/${file}"
        else
            file="${url%%\?*}"; file="${file##*/}"
            target="${dir}/${file}"
        fi
        if [[ -s $target ]]; then
            printf "Skipping (exists): %s\n" "${file}"
            continue
        fi
        printf "Downloading (extra): %s -> %s\n" "${url}" "${target}"
        provisioning_download "${url}" "${target}"
    done
}

# The abetlen cu124 llama-cpp wheel dynamically loads libcublas.so.12 etc.
# Those live in the venv's nvidia-* pip packages, not on the default loader
# path -> llama_cpp import dies with "libcublas.so.12: cannot open shared
# object file". supervisor-comfyui.sh sources environment.sh, so exporting
# there covers comfyui (and jupyter etc.). Idempotent.
function provisioning_ld_library_path() {
    envfile=/opt/ai-dock/etc/environment.sh
    marker="# krea2-vnccs: nvidia venv libs for llama-cpp cu124 wheel"
    grep -qF "$marker" "$envfile" && { printf "LD_LIBRARY_PATH already set (skipping)\n"; return 0; }
    libdirs=$(ls -d /opt/environments/python/comfyui/lib/python3.10/site-packages/nvidia/*/lib 2>/dev/null | tr '\n' ':')
    [[ -z $libdirs ]] && { printf "WARN: no nvidia lib dirs found\n"; return 0; }
    printf '\n%s\nexport LD_LIBRARY_PATH="%s${LD_LIBRARY_PATH:-}"\n' "$marker" "$libdirs" >> "$envfile"
    printf "LD_LIBRARY_PATH exported via environment.sh\n"
}

# Runpod's edge proxy rewrites Host to an internal CGNAT ip:port, so
# VNCCS's validate_privileged_request (Host vs Origin netloc compare)
# 403s every state-changing UI call behind *.proxy.runpod.net.
# Patch: trust private/CGNAT hosts as proxy-rewritten; the
# Sec-Fetch-Site cross-site check still guards real cross-origin abuse.
# Idempotent; same logic as vnccs-proxy-fix.sh. Refuses loudly if VNCCS
# upstream changed the target block (re-derive patch, see wiki).
# NOTE: clone dir follows the repo name (ComfyUI_VNCCS), not the
# registry id (vnccs) — patch path must match.
function provisioning_patch_vnccs_proxy() {
    target="/opt/ComfyUI/custom_nodes/ComfyUI_VNCCS/utils.py"
    [[ -f $target ]] || { printf "vnccs utils.py not found at %s - patch NOT applied, downloads via UI will 403\n" "$target"; return 0; }
    if grep -q '100.64.0.0/10' "$target"; then
        printf "vnccs proxy patch already present (skipping)\n"
        return 0
    fi
    cp -n "$target" "$target.bak-podproxy"
    python3 - "$target" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
if "import ipaddress" not in src:
    src = src.replace(
        "from urllib.parse import urlparse",
        "import ipaddress\nfrom urllib.parse import urlparse", 1)
old = """        elif parsed.netloc and host:
            raise ValueError("cross-origin privileged request rejected")"""
new = """        elif parsed.netloc and host:
            # Runpod edge proxy rewrites Host to an internal CGNAT ip:port,
            # so behind it Host never matches Origin. Trust private/CGNAT
            # hosts as proxy-rewritten; cross-site callers are still stopped
            # by the Sec-Fetch-Site check below and by caddy auth.
            hostname = host.rsplit(":", 1)[0] if ":" in host else host
            proxied = False
            try:
                ip = ipaddress.ip_address(hostname)
                proxied = ip.is_private or ip.is_loopback or ip in ipaddress.ip_network("100.64.0.0/10")
            except ValueError:
                proxied = False
            if proxied:
                same_origin = True
            else:
                raise ValueError("cross-origin privileged request rejected")"""
if old not in src:
    sys.exit("ERROR: vnccs validate_privileged_request block changed upstream - manual patch needed")
open(path, "w").write(src.replace(old, new, 1))
print("vnccs proxy patch applied")
PY
}

# Auth header for known gated hosts; aria2 (multi-connection) preferred,
# wget fallback. Downloads to explicit target path, resumable.
function provisioning_download() {
    url="$1"; target="$2"
    auth_header=""
    if [[ -n $HF_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_header="Authorization: Bearer ${HF_TOKEN}"
    elif [[ -n $CIVITAI_TOKEN && $url =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.(com|red)(/|$|\?) ]]; then
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

# Optional private post-provisioning hook: store a base64-encoded script in
# a Runpod secret, reference it as CUSTOM_PROVISION_B64. Runs after models
# land and link pass, before the comfyui restart. Keeps private URLs/config
# out of this public repo. Hook scripts must NOT restart services or run
# the link pass themselves (handled after).
function provisioning_custom_hook() {
    [[ -z ${CUSTOM_PROVISION_B64:-} ]] && return 0
    printf "Running custom provisioning hook...\n"
    printf "%s" "${CUSTOM_PROVISION_B64}" | tr -d "[:space:]" | base64 -di > /tmp/custom_provision.sh
    bash /tmp/custom_provision.sh
    rc=$?
    rm -f /tmp/custom_provision.sh
    return $rc
}

# ComfyUI caches its model list at startup and may already be running.
function provisioning_restart_services() {
    supervisorctl restart comfyui comfyui_api_wrapper || true
}

function provisioning_print_header() {
    printf "\n##############################################\n#          Provisioning container            #\n#    krea2+VNCCS: ~52GB, takes a while       #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

provisioning_start
