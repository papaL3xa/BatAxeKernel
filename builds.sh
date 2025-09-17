#!/bin/bash

#===========================================================
# Kernel Build Script - BatAxe (Full Ready-to-Build Version)
#===========================================================

separator () { echo "---------------------------------------------------------"; }
quotes () { echo "-- $1..."; }
noquotes () { echo "-- $1"; }

clean () {
    quotes "Cleanup Build Files"
    rm -rf o* .w* "$(pwd)/AIK-Linux/s*" "$(pwd)/AIK-Linux/ramdisk/f*" build/*.p* build/*er* arch/arm64/configs/"$KERNEL_DEFCONFIG"
    git restore arch/arm64/configs/"$KERNEL_DEFCONFIG" 2>/dev/null

    if [[ "$CLEAN" == "y" ]]; then
        quotes "Revert all changes to latest commit (All uncommitted changes will be lost!)"
        rm -rf K* toolc* build/A* build/d* build/m* build/s* build/u*
        git clean -df
        git reset --hard HEAD
    fi
}

abort () {
    echo "Working dir: $(pwd)"
    [[ "$LOCAL" == "y" ]] && clean
    quotes "Failed to Compile Kernel! Exiting"
    exit 1
}

check () {
    if [ $? -eq 0 ]; then
        echo "-- Setup $1 Done!"
    else
        quotes "Failed! Cancel the Script"
        abort
    fi
}

submodule () {
    quotes "Fetch all Submodules Update"
    git submodule update -f -q --init --recursive > /dev/null
    check "Submodules"
}

usage () {
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the Model Code of the Phone (default: d2s)
    -k, --ksu [y/N]        Include KernelSU Next with SuSFS (default: y)
    -h, --help             List all Build Script Command
    -c, --clean [y/N]      Reset all changes to latest commit [!! Your uncommitted changes will be lost !!] (default: n)
    -l, --llvm [value]     Clang (12-18) or Neutron Clang Version (default: 10032024)
EOF
}

kernelsu () {
    if test -d "KernelSU-Next"; then
            rm -rf Ke*
        fi

    if [[ ! -d "KernelSU-Next" ]]; then
        quotes "Adding KernelSU Next Submodule"
        git submodule add -b next-susfs-experimental https://github.com/sidex15/KernelSU-Next.git > /dev/null
        git submodule update --init --recursive
        bash <(curl -LSs "https://raw.githubusercontent.com/sidex15/KernelSU-Next/refs/heads/next-susfs-experimental/kernel/setup.sh")
    fi

    KSU_NEXT="ksu.config"
    check "KernelSU Next"
}

#===========================================================
# Parse CLI arguments
#===========================================================
USE_NEUTRON=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m) MODEL="$2"; shift 2 ;;
        --ksu|-k) KSU="$2"; shift 2 ;;
        --ver|-v) KERNEL_VERSION="$2"; shift 2 ;;
        --rel|-r) RELEASE="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --clean|-c) CLEAN="$2"; shift 2 ;;
        --llvm|-l)
            LLVM="$2"
            if [[ -z "$LLVM" ]]; then
                LLVM=10032024
                USE_NEUTRON=true
            elif [[ "$LLVM" -ge 12 ]] && [[ "$LLVM" -le 18 ]]; then
                USE_NEUTRON=false
            else
                USE_NEUTRON=true
            fi
            shift 2
            ;;
        *) usage; exit 1 ;;
    esac
done

#===========================================================
# Default values
#===========================================================
[[ -z "$MODEL" ]] && MODEL=d2s
[[ -z "$KSU" ]] && KSU=y
[[ -z "$CLEAN" ]] && CLEAN=n
[[ -z "$KERNEL_VERSION" ]] && KERNEL_VERSION=Unofficial

KERNEL_DEFCONFIG="bataxe-${MODEL}_defconfig"

case $MODEL in
    beyond0lte) SOC=0; BOARD=SRPRI28A014KU ;;
    beyond1lte) SOC=0; BOARD=SRPRI28B014KU ;;
    beyond2lte) SOC=0; BOARD=SRPRI17C014KU ;;
    beyondx) SOC=0; BOARD=SRPSC04B011KU ;;
    d1) SOC=5; BOARD=SRPSD26B007KU ;;
    d1xks) SOC=5; BOARD=SRPSD23A002KU ;;
    d2s) SOC=5; BOARD=SRPSC14B007KU ;;
    d2x) SOC=5; BOARD=SRPSC14C007KU ;;
    *) usage; exit 1 ;;
esac

#===========================================================
# Detect Environment & download dependencies
#===========================================================
detect_env () {
    DATE=$(date +"%Y%m%d")
    BUILD_URL="https://raw.githubusercontent.com/papaL3xa/build/refs/heads/exynos9820/"
    REPO_URL="https://raw.githubusercontent.com/ivanmeler/android_kernel_samsung_beyondlte/refs/heads/oneui5_beyond/"
    KERNEL_NAME=BatAxe
    export KBUILD_BUILD_USER=papaL3xa
    export KBUILD_BUILD_HOST=BatAxeKernel

    DEVICE=$([[ "$SOC" == "5" ]] && echo "Note10" || echo "S10")
    [[ ! -z $RELEASE ]] && quotes "Running on GitHub Actions" && echo BUILD_DEVICE=$DEVICE >> $GITHUB_ENV || LOCAL=y

    # Create directories
    mkdir -p "$(pwd)/AIK-Linux/ramdisk" build/dtconfigs build/out/$MODEL build/out/$MODEL/zip build/export

    # Download required ramdisk files
    [[ ! -f "$(pwd)/AIK-Linux/ramdisk/dpolicy" ]] && curl -LSs "${REPO_URL}ramdisk/ramdisk/dpolicy" -o "$(pwd)/AIK-Linux/ramdisk/dpolicy"
    [[ ! -f "$(pwd)/AIK-Linux/ramdisk/init" ]] && curl -LSs "${REPO_URL}ramdisk/ramdisk/init" -o "$(pwd)/AIK-Linux/ramdisk/init" && chmod +x "$(pwd)/AIK-Linux/ramdisk/init"
    [[ ! -f "$(pwd)/AIK-Linux/ramdisk/fstab.exynos982$SOC" ]] && curl -LSs "${REPO_URL}ramdisk/fstab.exynos982$SOC" -o "$(pwd)/AIK-Linux/ramdisk/fstab.exynos982$SOC"

    # Download required binaries
    [[ ! -f "build/mkdtimg" ]] && curl -LSs "${REPO_URL}toolchains/mkdtimg" -o build/mkdtimg && chmod +x build/mkdtimg
    [[ ! -f "build/module-binary" ]] && curl -LSs "https://raw.githubusercontent.com/Zackptg5/MMT-Extended/refs/heads/master/META-INF/com/google/android/update-binary" -o build/module-binary
    [[ ! -f "build/update-binary" ]] && curl -LSs "${REPO_URL}toolchains/update-binary" -o build/update-binary
    [[ ! -f "build/updater-script" ]] && curl -LSs "${BUILD_URL}updater-script" -o build/updater-script
    [[ ! -f "build/module.prop" ]] && curl -LSs "${BUILD_URL}module.prop" -o build/module.prop
    [[ ! -f "build/system.prop" ]] && curl -LSs "${BUILD_URL}system.prop" -o build/system.prop

    check "Environment Setup & Dependencies"
}

#===========================================================
# Toolchain setup (Neutron Clang included)
#===========================================================
toolchain () {
    if [[ "$USE_NEUTRON" == "true" ]]; then
        KERNELCLANG="NeutronClang-$LLVM"
        CLANG_INFO="Neutron Clang ($LLVM)"
        TOOLCHAIN_PATH="toolchain/neutron-$LLVM"
        mkdir -p "$TOOLCHAIN_PATH"
        quotes "Download & Setup Neutron Clang ($LLVM)"

        pushd "$TOOLCHAIN_PATH" > /dev/null
        bash <(curl -LSs "https://raw.githubusercontent.com/Neutron-Toolchains/antman/refs/heads/main/antman") -S=$LLVM
        check "Neutron Clang Setup"
        bash <(curl -LSs "https://raw.githubusercontent.com/Neutron-Toolchains/antman/refs/heads/main/antman") --patch=glibc
        popd > /dev/null
    else
        KERNELCLANG="Clang$LLVM"
        CLANG_INFO="Clang $LLVM"
        TOOLCHAIN_PATH="toolchain/clang-$LLVM"
    fi

    PATH="$PWD/$TOOLCHAIN_PATH/bin:$PATH"
}

#===========================================================
# Build Kernel
#===========================================================
kernel () {
    noquotes "Fetch Kernel Info"
    noquotes "Device: $DEVICE ($MODEL)"
    noquotes "SOC: Exynos 982$SOC"
    noquotes "Defconfig: $KERNEL_DEFCONFIG"
    noquotes "Kernel Version: $KERNEL_VERSION"

    [[ -z "$KSU_NEXT" ]] && noquotes "KernelSU Next: Not Include" || noquotes "KernelSU Next: Include ($KSU_NEXT)"

    sed -i "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/" arch/arm64/configs/"$KERNEL_DEFCONFIG"
    sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" arch/arm64/configs/"$KERNEL_DEFCONFIG"

    quotes "Building Kernel Using $KERNEL_DEFCONFIG"
    make -j$(nproc --all) ARCH=arm64 O=out $KERNEL_DEFCONFIG || abort
    make -j$(nproc --all) ARCH=arm64 O=out || abort
    quotes "Finished Kernel Build!"
}

#===========================================================
# Build DTB
#===========================================================
dtb () {
    quotes "Building Device Tree Blob Image for Exynos 982$SOC"
    ./build/mkdtimg cfg_create build/out/$MODEL/dtb_exynos982$SOC.img build/dtconfigs/exynos982$SOC.cfg -d out/arch/arm64/boot/dts/exynos
    quotes "Building DTBO Image for $DEVICE ($MODEL)"
    ./build/mkdtimg cfg_create build/out/$MODEL/dtbo_$MODEL.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung
}

#===========================================================
# Build Ramdisk
#===========================================================
ramdisk () {
    quotes "Building Ramdisk"
    mkdir -p "$(pwd)/AIK-Linux/split_img"
    pushd "$(pwd)/AIK-Linux/split_img" > /dev/null
    cp ../../../out/arch/arm64/boot/Image boot.img-kernel
    echo -e "0x10000000" > boot.img-base
    echo -e $BOARD > boot.img-board
    echo -e "loop.max_part=7" > boot.img-cmdline
    echo -e "sha1" > boot.img-hashtype
    echo -e "1" > boot.img-header_version
    echo -e "AOSP" > boot.img-imgtype
    echo -e "0x00008000" > boot.img-kernel_offset
    echo -e "45285376" > boot.img-origsize
    echo -e "2023-04" > boot.img-os_patch_level
    echo -e "12.0.0" > boot.img-os_version
    echo -e "2048" > boot.img-pagesize
    echo -e "0x01000000" > boot.img-ramdisk_offset
    echo -e "gzip" > boot.img-ramdiskcomp
    echo -e "0xf0000000" > boot.img-second_offset
    echo -e "0x00000100" > boot.img-tags_offset
    popd > /dev/null
}

#===========================================================
# Build Zip
#===========================================================
build_zip () {
    quotes "Building Zip"
    NAME="BatAxe-$MODEL-$KERNEL_VERSION-$DATE.zip"
    pushd build/out/$MODEL/zip > /dev/null
    zip -r ../"$NAME" .
    popd > /dev/null
    mv build/out/$MODEL/zip/"$NAME" build/export/
    quotes "Zip Created: build/export/$NAME"
}

#===========================================================
# Main
#===========================================================
rm -rf ./build.log
(
    START=$(date +%s)

    quotes "Preparing Build Environment"
    detect_env
    toolchain
    pushd $(dirname "$0") > /dev/null

    [[ "$LOCAL" == "y" ]] && submodule
    [[ "$KSU" == "y" ]] && kernelsu

    kernel
    dtb
    ramdisk
    build_zip

    [[ "$LOCAL" == "y" ]] && clean

    END=$(date +%s)
    ELAPSED=$((END-START))
    quotes "Total Compile Time: $((ELAPSED / 60)) Minutes and $((ELAPSED % 60)) Seconds"
) 2>&1 | tee -a ./build.log
