#!/bin/bash

# BatAxe Kernel Build Script
# Enhanced version with better error handling, logging, and maintainability

set -euo pipefail

# Color codes for better output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly BUILD_LOG="${SCRIPT_DIR}/build.log"
readonly START_TIME=$(date +%s)

# Default configuration
MODEL="d2s"
KSU_OPTION="y"
KERNEL_VERSION="Unofficial"
RELEASE=""
CLEAN="n"
LLVM=""
USE_NEUTRON=false
NEUTRON="10032024"
LOCAL="n"

# Model configuration
declare -A MODEL_CONFIG=(
    ["beyond0lte"]="0 SRPRI28A014KU"
    ["beyond1lte"]="0 SRPRI28B014KU" 
    ["beyond2lte"]="0 SRPRI17C014KU"
    ["beyondx"]="0 SRPSC04B011KU"
    ["d1"]="5 SRPSD26B007KU"
    ["d1xks"]="5 SRPSD23A002KU"
    ["d2s"]="5 SRPSC14B007KU"
    ["d2x"]="5 SRPSC14C007KU"
)

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$BUILD_LOG"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$BUILD_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$BUILD_LOG"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$BUILD_LOG"
}

separator() {
    echo "---------------------------------------------------------" | tee -a "$BUILD_LOG"
}

header() {
    separator
    log "$1"
    separator
}

# Utility functions
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found. Please install it."
        return 1
    fi
    return 0
}

download_file() {
    local url="$1"
    local output="$2"
    local retries=3
    
    for ((i=1; i<=retries; i++)); do
        if curl -fLSs --retry 3 --retry-delay 2 "$url" -o "$output"; then
            return 0
        fi
        warn "Download attempt $i failed for $url"
        sleep 2
    done
    
    error "Failed to download $url after $retries attempts"
    return 1
}

check_exit_status() {
    local exit_code=$?
    local operation="$1"
    
    if [ $exit_code -eq 0 ]; then
        log "$operation completed successfully"
    else
        error "$operation failed with exit code $exit_code"
        abort
    fi
}

# Core functions
clean() {
    header "Cleaning Build Files"

    rm -rf out* .w* build/AIK/split_img* build/AIK/ramdisk/fstab* build/*.prop build/*er* arch/arm64/configs/ksu.config
    
    if [[ -n "$KERNEL_DEFCONFIG" ]]; then
        git restore "arch/arm64/configs/$KERNEL_DEFCONFIG" 2>/dev/null || true
    fi

    if [[ "$CLEAN" == "y" ]]; then
        header "Performing Deep Clean (All uncommitted changes will be lost!)"
        rm -rf KernelSU* toolchain* build/AIK/build build/dtconfigs build/export
        git clean -df
        git reset --hard HEAD
        log "Deep clean completed"
    fi
}

abort() {
    cd "$SCRIPT_DIR"
    
    if [[ "$LOCAL" == "y" ]]; then
        clean
    fi
    
    header "Build Failed!"
    exit 1
}

trap abort ERR

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

Build BatAxe Kernel for Samsung Exynos 9820 devices

Options:
    -m, --model MODEL      Specify device model (default: d2s)
                          Supported: ${!MODEL_CONFIG[@]}
    -k, --ksu [y/N]        Include KernelSU Next with SuSFS (default: y)
    -v, --version VER      Set kernel version (default: Unofficial)
    -r, --release [y/N]    Release build mode for GitHub Actions
    -c, --clean [y/N]      Clean build files (default: n)
                         Use 'y' for deep clean (WARNING: loses uncommitted changes)
    -l, --llvm VER         Clang version (12-21) or Neutron Clang (default: neutron)
    -h, --help            Show this help message

Examples:
    $SCRIPT_NAME -m d2s -k y -l 17
    $SCRIPT_NAME --model d2s --clean y
    $SCRIPT_NAME --help

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--model)
                MODEL="$2"
                if [[ ! -v MODEL_CONFIG[$MODEL] ]]; then
                    error "Unknown model: $MODEL"
                    usage
                    exit 1
                fi
                shift 2
                ;;
            -k|--ksu)
                KSU_OPTION="${2,,}"
                if [[ ! "$KSU_OPTION" =~ ^(y|n)$ ]]; then
                    error "Invalid KSU option: $KSU_OPTION"
                    usage
                    exit 1
                fi
                shift 2
                ;;
            -v|--version)
                KERNEL_VERSION="$2"
                shift 2
                ;;
            -r|--release)
                RELEASE="${2,,}"
                shift 2
                ;;
            -c|--clean)
                CLEAN="${2,,}"
                if [[ ! "$CLEAN" =~ ^(y|n)$ ]]; then
                    error "Invalid clean option: $CLEAN"
                    usage
                    exit 1
                fi
                shift 2
                ;;
            -l|--llvm)
                LLVM="$2"
                if [[ "$LLVM" =~ ^[0-9]+$ ]] && [[ "$LLVM" -ge 12 ]] && [[ "$LLVM" -le 21 ]]; then
                    USE_NEUTRON=false
                else
                    USE_NEUTRON=true
                    [[ -n "$2" && "$2" != -* ]] && NEUTRON="$2"
                fi
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

setup_environment() {
    header "Setting Up Build Environment"
    
    # Set build variables
    readonly DATE=$(date +"%Y%m%d")
    readonly BUILD_URL="https://raw.githubusercontent.com/papaL3xa/builds/refs/heads/exynos9820/"
    readonly REPO_URL="https://raw.githubusercontent.com/ivanmeler/android_kernel_samsung_beyondlte/refs/heads/oneui5_beyond/"
    readonly KERNEL_NAME="BatAxeKernel"
    
    export KBUILD_BUILD_USER="papaL3xa"
    export KBUILD_BUILD_HOST="BatAxeKernel"
    
    # Parse model configuration
    if [[ -v MODEL_CONFIG[$MODEL] ]]; then
        IFS=' ' read -r SOC BOARD <<< "${MODEL_CONFIG[$MODEL]}"
    else
        error "Invalid model: $MODEL"
        exit 1
    fi
    
    # Set device type
    if [[ "$SOC" == "5" ]]; then
        DEVICE="Note10"
    else
        DEVICE="S10"
    fi
    
    KERNEL_DEFCONFIG="bataxe-${MODEL}_defconfig"
    
    # Detect environment
    if [[ -n "$RELEASE" ]]; then
        log "Running on GitHub Actions"
        echo "BUILD_DEVICE=$DEVICE" >> "$GITHUB_ENV"
    else
        log "Running on Local Machine"
        LOCAL="y"
    fi
    
    # Setup directories and dependencies
    setup_dependencies
}

setup_dependencies() {
    # Check required commands
    check_command curl
    check_command git
    check_command make
    check_command zip
    
    # Setup Android Image Kitchen
    if [[ ! -d "build/AIK" ]]; then
        log "Adding Android Image Kitchen as submodule"
        git submodule add -f -q https://github.com/papaL3xa/Android-Image-Kitchen build/AIK > /dev/null
        chmod +x build/AIK/mk*
    fi
    
    # Setup ramdisk files
    setup_ramdisk
    
    # Setup DTB tools
    setup_dtb_tools
    
    # Setup build scripts
    setup_build_scripts
}

setup_ramdisk() {
    mkdir -p build/AIK/ramdisk
    
    local ramdisk_files=("dpolicy" "init")
    for file in "${ramdisk_files[@]}"; do
        if [[ ! -f "build/AIK/ramdisk/$file" ]]; then
            log "Downloading ramdisk file: $file"
            download_file "${REPO_URL}ramdisk/ramdisk/$file" "build/AIK/ramdisk/$file"
            [[ "$file" == "init" ]] && chmod +x "build/AIK/ramdisk/$file"
        fi
    done
    
    # Setup fstab
    if [[ ! -f "build/AIK/ramdisk/fstab.exynos982$SOC" ]]; then
        log "Downloading fstab for Exynos 982$SOC"
        download_file "${REPO_URL}ramdisk/fstab.exynos982$SOC" "build/AIK/ramdisk/fstab.exynos982$SOC"
    fi
}

setup_dtb_tools() {
    if [[ ! -f "build/mkdtimg" ]]; then
        log "Downloading DTB build script"
        download_file "${REPO_URL}toolchains/mkdtimg" "build/mkdtimg"
        chmod +x build/mkdtimg
    fi
    
    mkdir -p build/dtconfigs
    
    local dtb_configs=("exynos982$SOC.cfg" "$MODEL.cfg")
    for config in "${dtb_configs[@]}"; do
        if [[ ! -f "build/dtconfigs/$config" ]]; then
            log "Downloading DTB config: $config"
            local source_config="$config"
            [[ "$config" == "$MODEL.cfg" && "$MODEL" == "d1xks" ]] && source_config="d1x.cfg"
            download_file "${REPO_URL}toolchains/configs/$source_config" "build/dtconfigs/$config"
            
            # Special handling for d2s model
            [[ "$MODEL" == "d2s" ]] && sed -i "s/d2/$MODEL/g" "build/dtconfigs/$config"
        fi
    done
}

setup_build_scripts() {
    local build_files=(
        "module.prop"
        "system.prop" 
        "updater-script"
    )
    
    for file in "${build_files[@]}"; do
        if [[ ! -f "build/$file" ]]; then
            log "Downloading build file: $file"
            download_file "${BUILD_URL}$file" "build/$file"
        fi
    done
    
    if [[ ! -f "build/module-binary" ]]; then
        log "Downloading module binary"
        download_file "https://raw.githubusercontent.com/Zackptg5/MMT-Extended/refs/heads/master/META-INF/com/google/android/update-binary" "build/module-binary"
    fi
    
    if [[ ! -f "build/update-binary" ]]; then
        log "Downloading kernel zip binary"
        download_file "${REPO_URL}toolchains/update-binary" "build/update-binary"
    fi
}

setup_toolchain() {
    header "Setting Up Toolchain"
    
    if [[ "$USE_NEUTRON" == "true" ]]; then
        setup_neutron_clang
    else
        setup_llvm_clang
    fi
    
    log "Using toolchain: $CLANG_INFO"
}

setup_neutron_clang() {
    KERNELCLANG="NeutronClang-$NEUTRON"
    CLANG_INFO="Neutron Clang ($NEUTRON)"
    TOOLCHAIN_PATH="toolchain/neutron-$NEUTRON"
    
    if [[ ! -d "$TOOLCHAIN_PATH" ]]; then
        log "Adding Neutron Clang as submodule"
        git submodule add -f -q "https://gitlab.com/dakkshesh07/neutron-clang.git" "$TOOLCHAIN_PATH" > /dev/null
    fi
    
    export PATH="$PWD/$TOOLCHAIN_PATH/bin:$PATH"
    
    ARGS="ARCH=arm64 O=out LLVM=1 LLVM_IAS=1"
}

setup_llvm_clang() {
    local clang_versions=(
        ["12"]="416183b1 .0.7 hub ArrowOS-Devices"
        ["13"]="433403b .0.3 lab crdroidandroid" 
        ["14"]="450784 .0.3 lab crdroidandroid"
        ["15"]="468909b .0.3 lab crdroidandroid"
        ["16"]="475365b .0.2 lab crdroidandroid"
        ["17"]="498229b .0.4 lab crdroidandroid"
        ["18"]="522817 .0.1 lab crdroidandroid"
        ["19"]="536225 .0.1 lab crdroidandroid"
        ["20"]="547379 .0.0 lab crdroidandroid"
        ["21"]="563880 .0.0 lab reaPeR1010"
    )
    
    LLVM="${LLVM:-21}"
    if [[ ! -v clang_versions[$LLVM] ]]; then
        warn "Unsupported LLVM version: $LLVM, defaulting to 21"
        LLVM=21
    fi
    
    IFS=' ' read -r CLANG MINOR HOST ROM <<< "${clang_versions[$LLVM]}"
    
    KERNELCLANG="Clang$LLVM"
    CLANG_VERSION="r$CLANG"
    CLANG_INFO="Clang $LLVM$MINOR (Based on $CLANG_VERSION)"
    TOOLCHAIN_PATH="toolchain/clang-$CLANG_VERSION"
    TOOLCHAIN_URL="https://git$HOST.com/$ROM/android_prebuilts_clang_host_linux-x86_clang-$CLANG_VERSION.git"
    
    if [[ ! -d "$TOOLCHAIN_PATH" ]]; then
        log "Adding $CLANG_INFO as submodule"
        git submodule add -f -q "$TOOLCHAIN_URL" "$TOOLCHAIN_PATH" > /dev/null
    fi
    
    export PATH="$PWD/$TOOLCHAIN_PATH/bin:$PATH"
    
    ARGS="ARCH=arm64 O=out LLVM=1 LLVM_IAS=1 CC=clang READELF=llvm-readelf"
}

setup_kernelsu() {
    header "Setting Up KernelSU"
    
    if [[ "$KSU_OPTION" != "y" ]]; then
        log "KernelSU disabled by user"
        return 0
    fi
    
    KSU_NEXT="ksu.config"
    
    # Clean up existing KernelSU directories
    rm -rf KernelSU-Next* KernelSU
    
    # Add KernelSU as submodule
    log "Adding KernelSU Next as submodule"
    git submodule add -f -q https://github.com/papaL3xa/KernelSU-Next-gorhanhee.git KernelSU-Next > /dev/null
    
    # Run KernelSU setup script
    local setup_url="https://raw.githubusercontent.com/papaL3xa/KernelSU-Next-gorhanhee/2e9038e96c0f7a05d0a36daf331b7cc6d1ab17e4/kernel/setup.sh"
    if curl -LSs "$setup_url" | bash -; then
        log "KernelSU setup completed"
    else
        warn "KernelSU setup script execution failed"
    fi
    
    # Download KernelSU config
    if [[ ! -f "arch/arm64/configs/$KSU_NEXT" ]]; then
        log "Downloading KernelSU config"
        download_file "${BUILD_URL}configs/$KSU_NEXT" "arch/arm64/configs/$KSU_NEXT"
    fi
}

build_kernel() {
    header "Building Kernel"
    
    # Display build information
    cat << EOF | tee -a "$BUILD_LOG"
Device: $DEVICE ($MODEL)
SOC: Exynos 982$SOC
Defconfig: $KERNEL_DEFCONFIG
Kernel Version: $KERNEL_VERSION
Build Date: $(date +"%Y-%m-%d")
KernelSU: $([[ "$KSU_OPTION" == "y" ]] && echo "Enabled" || echo "Disabled")
Toolchain: $CLANG_INFO
EOF

    # Update kernel version in defconfig
    sed -i "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/" "arch/arm64/configs/$KERNEL_DEFCONFIG"
    sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" "arch/arm64/configs/$KERNEL_DEFCONFIG"

    # Prepare defconfig
    local defconfigs=("$KERNEL_DEFCONFIG" "bataxe.config")
    [[ "$KSU_OPTION" == "y" ]] && defconfigs+=("$KSU_NEXT")

    # Generate configuration
    log "Generating kernel configuration"
    make -j"$(nproc --all)" $ARGS "${defconfigs[@]}"
    check_exit_status "Kernel configuration"

    # Build kernel
    log "Compiling kernel"
    make -j"$(nproc --all)" $ARGS
    check_exit_status "Kernel compilation"

    log "Kernel build completed successfully"
}

build_dtb() {
    header "Building Device Tree Blobs"
    
    log "Building DTB for Exynos 982$SOC"
    ./build/mkdtimg cfg_create "build/out/$MODEL/dtb_exynos982$SOC.img" "build/dtconfigs/exynos982$SOC.cfg" -d out/arch/arm64/boot/dts/exynos
    check_exit_status "DTB creation"
    
    log "Building DTBO for $MODEL"
    ./build/mkdtimg cfg_create "build/out/$MODEL/dtbo_$MODEL.img" "build/dtconfigs/$MODEL.cfg" -d out/arch/arm64/boot/dts/samsung
    check_exit_status "DTBO creation"
}

build_ramdisk() {
    header "Building Ramdisk"
    
    local aik_dir="build/AIK"
    rm -rf "$aik_dir/split_img"
    mkdir -p "$aik_dir/split_img"
    
    # Prepare split_img files
    cat > "$aik_dir/split_img/boot.img-base" <<< "0x10000000"
    cat > "$aik_dir/split_img/boot.img-board" <<< "$BOARD"
    cat > "$aik_dir/split_img/boot.img-cmdline" <<< "loop.max_part=7"
    cat > "$aik_dir/split_img/boot.img-hashtype" <<< "sha1"
    cat > "$aik_dir/split_img/boot.img-header_version" <<< "1"
    cat > "$aik_dir/split_img/boot.img-imgtype" <<< "AOSP"
    cat > "$aik_dir/split_img/boot.img-kernel_offset" <<< "0x00008000"
    cat > "$aik_dir/split_img/boot.img-origsize" <<< "45285376"
    cat > "$aik_dir/split_img/boot.img-os_patch_level" <<< "2023-04"
    cat > "$aik_dir/split_img/boot.img-os_version" <<< "12.0.0"
    cat > "$aik_dir/split_img/boot.img-pagesize" <<< "2048"
    cat > "$aik_dir/split_img/boot.img-ramdisk_offset" <<< "0x01000000"
    cat > "$aik_dir/split_img/boot.img-ramdiskcomp" <<< "gzip"
    cat > "$aik_dir/split_img/boot.img-second_offset" <<< "0xf0000000"
    cat > "$aik_dir/split_img/boot.img-tags_offset" <<< "0x00000100"
    
    # Copy kernel image
    cp "out/arch/arm64/boot/Image" "$aik_dir/split_img/boot.img-kernel"
    
    # Create ramdisk directories
    mkdir -p "$aik_dir/ramdisk/"{debug_ramdisk,dev,mnt,proc,sys}
    
    # Build boot image
    pushd "$aik_dir" > /dev/null
    log "Creating boot image with Android Image Kitchen"
    ./mkimg
    popd > /dev/null
    
    check_exit_status "Ramdisk creation"
}

build_flashable_zip() {
    header "Creating Flashable ZIP"
    
    local zip_dir="build/out/$MODEL/zip"
    local export_dir="build/export"
    
    # Clean and create directories
    rm -rf "$zip_dir" "$export_dir"
    mkdir -p "$zip_dir/META-INF/com/google/android"
    mkdir -p "$zip_dir/module/"{common,META-INF/com/google/android}
    mkdir -p "$export_dir"
    
    # Copy files to zip directory
    cp "build/AIK/image-new.img" "build/out/$MODEL/boot-patched.img"
    cp "build/out/$MODEL/boot-patched.img" "$zip_dir/boot.img"
    cp "build/out/$MODEL/dtb_exynos982$SOC.img" "$zip_dir/dtb.img"
    cp "build/out/$MODEL/dtbo_$MODEL.img" "$zip_dir/dtbo.img"
    cp "build/update-binary" "$zip_dir/META-INF/com/google/android/"
    cp "build/updater-script" "$zip_dir/META-INF/com/google/android/"
    cp "build/module.prop" "$zip_dir/module/"
    cp "build/system.prop" "$zip_dir/module/common/"
    cp "build/module-binary" "$zip_dir/module/META-INF/com/google/android/update-binary"
    
    # Create module updater-script
    echo "#MAGISK" > "$zip_dir/module/META-INF/com/google/android/updater-script"
    
    # Create module zip
    pushd "$zip_dir/module" > /dev/null
    zip -r9 "../module.zip" . > /dev/null
    popd > /dev/null
    rm -rf "$zip_dir/module"
    
    # Update updater-script with build information
    sed -i "s/ui_print(\" Kernel Version: \");/ui_print(\" Kernel Version: $KERNEL_VERSION\");/" "$zip_dir/META-INF/com/google/android/updater-script"
    sed -i "s/ui_print(\" Kernel Device: \");/ui_print(\" Kernel Device: $DEVICE ($MODEL)\");/" "$zip_dir/META-INF/com/google/android/updater-script"
    sed -i "s/ui_print(\" Kernel Toolchain: \");/ui_print(\" Kernel Toolchain: $CLANG_INFO\");/" "$zip_dir/META-INF/com/google/android/updater-script"
    
    # Create final zip for local/release builds
    if [[ "$LOCAL" == "y" || "$RELEASE" == "y" ]]; then
        # Update kernel version with date and toolchain info
        local version_suffix="$KERNEL_NAME-$KERNEL_VERSION-$DATE-$DEVICE-$MODEL-$KERNELCLANG"
        sed -i "s/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/CONFIG_LOCALVERSION=\"-$version_suffix\"/" "arch/arm64/configs/$KERNEL_DEFCONFIG"
        
        local zip_name="$version_suffix.zip"
        pushd "$zip_dir" > /dev/null
        zip -r9 "../$zip_name" . > /dev/null
        popd > /dev/null
        
        mv "build/out/$MODEL/$zip_name" "$export_dir/"
        log "Flashable ZIP created: $export_dir/$zip_name"
    fi
}

main() {
    # Initialize
    rm -f "$BUILD_LOG"
    parse_arguments "$@"
    
    {
        log "BatAxe Kernel Build Started"
        log "Script: $SCRIPT_NAME, Directory: $SCRIPT_DIR"
        
        setup_environment
        setup_toolchain
        
        # Fetch submodules for local builds
        if [[ "$LOCAL" == "y" ]]; then
            header "Fetching Submodules"
            git submodule update -f -q --init --recursive > /dev/null
            check_exit_status "Submodules update"
        fi
        
        setup_kernelsu
        build_kernel
        build_dtb
        build_ramdisk
        build_flashable_zip
        
        # Clean up for local builds
        if [[ "$LOCAL" == "y" ]]; then
            clean
        fi
        
        # Calculate and display build time
        local end_time=$(date +%s)
        local elapsed=$((end_time - START_TIME))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        
        header "Build Completed Successfully"
        log "Total build time: ${minutes}m ${seconds}s"
        
    } 2>&1 | tee -a "$BUILD_LOG"
}

# Run main function with all arguments
main "$@"