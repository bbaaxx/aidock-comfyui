#!/bin/false

build_nvidia_main() {
    build_nvidia_install_deps
    build_common_run_tests
    build_nvidia_run_tests
}

build_nvidia_install_deps() {
    short_cuda_version="cu$(cut -d '.' -f 1,2 <<< "${CUDA_VERSION}" | tr -d '.')"
    # TORCH_INDEX overrides the wheel index (e.g. cu130) when the torch build
    # targets a newer CUDA than the base image provides; wheels bundle their
    # own CUDA runtime, the host driver supplies compatibility.
    torch_index="${TORCH_INDEX:-$short_cuda_version}"
    # Companions optional: torchaudio/xformers lag torch releases and may
    # lack wheels for the chosen index. Empty version = package skipped.
    pkgs=("torch==${PYTORCH_VERSION}")
    [[ -n "${TORCHVISION_VERSION}" ]] && pkgs+=("torchvision==${TORCHVISION_VERSION}")
    [[ -n "${TORCHAUDIO_VERSION}" ]] && pkgs+=("torchaudio==${TORCHAUDIO_VERSION}")
    "$COMFYUI_VENV_PIP" install --no-cache-dir \
        "${pkgs[@]}" \
        --index-url="https://download.pytorch.org/whl/${torch_index}" \
        --extra-index-url="https://pypi.org/simple"
    # xformers separately: PyPI carries same versions built against a
    # different CUDA; must not let pip pick that one
    if [[ -n "${XFORMERS_VERSION}" ]]; then
        "$COMFYUI_VENV_PIP" install --no-cache-dir \
            "xformers==${XFORMERS_VERSION}" \
            --index-url="https://download.pytorch.org/whl/${torch_index}"
    fi
}

build_nvidia_run_tests() {
    installed_pytorch_cuda_version=$("$COMFYUI_VENV_PYTHON" -c "import torch; print(torch.version.cuda)")
    expected_cuda="${PYTORCH_CUDA_VERSION:-$CUDA_VERSION}"
    if [[ "$expected_cuda" != "$installed_pytorch_cuda"* ]]; then
        echo "Expected PyTorch CUDA ${expected_cuda} but found ${installed_pytorch_cuda}\n"
        exit 1
    fi
}

build_nvidia_main "$@"