#!/bin/bash

# FORK OVERRIDE (bbaaxx/aidock-comfyui): symlink-escape guard.
# Upstream resolves realpath() of the stored file, so a planted symlink on
# a (shared/persistent) volume would produce model-dir links pointing at
# arbitrary pod files (e.g. storage/evil.safetensors -> /etc/passwd).
# Only plain regular files inside storage are ever linked.

storage_dir="$1"
stored_file="$2"
event_type="$3"

if [[ -L $stored_file || ( -e $stored_file && ! -f $stored_file ) ]]; then
    printf "Refusing to link non-regular or symlinked storage file: %s\n" "$stored_file" >&2
    exit 0
fi

absolute_stored_file=$(realpath "$stored_file")
stored_file_parent_dir=$(realpath --relative-to="$storage_dir" "$(dirname "$stored_file")")

# Simplify per-image settings by keeping mappings separate
source /opt/ai-dock/storage_monitor/etc/mappings.sh

# Function to create symlinks for a given file and repository directory
manage_symlinks() {
    for mapped_storage_dir in "${!storage_map[@]}"; do
        if [[ $stored_file_parent_dir =~ ^$mapped_storage_dir(.*)$ ]]; then
            # For subdirectories of the app_directory
            unmapped_subdirs="${BASH_REMATCH[1]}"
            read -ra target_dirs <<< "${storage_map["$mapped_storage_dir"]}"
            for mapped_target_directory in "${target_dirs[@]}"; do
                symlink_target="${mapped_target_directory}${unmapped_subdirs}/$(basename "$stored_file")"
                symlink_target_dir="$(dirname "$symlink_target")"
                if [[ -e "$absolute_stored_file" && (! -e "$symlink_target" || -L "$symlink_target") ]]; then
                    # Create symlinks for existing or newly created files
                    mkdir -p "$symlink_target_dir"
                    # Always delete first to avoid recursive symlink issue
                    rm -f "$symlink_target"
                    ln -sv "$absolute_stored_file" "$symlink_target"
                else
                    # Remove symlink for deleted files
                    if [[ -L $symlink_target ]]; then
                        rm -f "$symlink_target"
                    fi
                fi
            done
        fi
    done
}

# Call the function to create or remove symlinks for the stored file
manage_symlinks
