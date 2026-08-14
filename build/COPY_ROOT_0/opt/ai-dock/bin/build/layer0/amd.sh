#!/bin/false

build_amd_main() {
    build_amd_install_deps
    build_common_run_tests
}

build_amd_install_deps() {
    "$COMFYUI_VENV_PIP" install --no-cache-dir \
        torch==${PYTORCH_VERSION} \
        torchvision==${TORCHVISION_VERSION:-0.20.1} \
        torchaudio==${TORCHAUDIO_VERSION:-2.5.1} \
        --index-url=https://download.pytorch.org/whl/rocm${ROCM_VERSION}
}

build_amd_main "$@"