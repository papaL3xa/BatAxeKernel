#!/bin/bash

# =============================================================================
# KERNEL BUILD SCRIPT FOR EXYNOS 9820 DEVICES
# =============================================================================

# =============================================================================
# FUNGSI UTILITY
# =============================================================================

separator() {
    echo "---------------------------------------------------------"
}

quotes() {
    echo "-- $1..."
}

noquotes() {
    echo "-- $1"
}

# =============================================================================
# FUNGSI CLEANUP
# =============================================================================

clean() {
    separator
    quotes "Cleanup Build Files"
    rm -rf out build/AIK/split_img build/AIK/ramdisk-new.cpio.gz build/AIK/image-new.img
    git restore arch/arm64/configs/$KERNEL_DEFCONFIG

    if [[ "$CLEAN" == "y" ]]; then
        separator
        quotes "Revert all Change to Latest Commit"
        separator
        git clean -df && git reset --hard HEAD
    fi
}

# =============================================================================
# FUNGSI ERROR HANDLING
# =============================================================================

abort() {
    cd -
    if [[ "$LOCAL" == "y" ]]; then
        clean
    fi
    separator
    quotes "Failed to Compile Kernel! Exiting"
    separator
    exit -1
}

check() {
    if [ $? -eq 0 ]; then
        echo "-- Setup $1 Done!"
    else
        quotes "Failed! Cancel the Script"
        abort
    fi
}

# =============================================================================
# FUNGSI SETUP ENVIRONMENT
# =============================================================================

setup_aik() {
    separator
    quotes "Setting up Android Image Kitchen"
    
    if test -d "build/AIK"; then
        quotes "Updating AIK to latest version"
        cd build/AIK
        git pull origin master
        cd ../..
    else
        quotes "Downloading latest AIK"
        rm -rf build/AIK
        git clone https://github.com/osm0sis/Android-Image-Kitchen.git build/AIK
    fi
    
    # Make scripts executable
    chmod +x build/AIK/*.sh
    chmod +x build/AIK/*.py 2>/dev/null || true
    
    check "Android Image Kitchen"
}

setup_ramdisk() {
    if test -f "build/AIK/ramdisk/dpolicy" && test -f "build/AIK/ramdisk/init"; then
        quotes "Ramdisk Binary Found!"
    else
        mkdir -p build/AIK/ramdisk
        if ! test -f "build/AIK/ramdisk/dpolicy"; then
            quotes "Getting Ramdisk dpolicy"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/dpolicy" -o build/AIK/ramdisk/dpolicy
        fi
        if ! test -f "build/AIK/ramdisk/init"; then
            quotes "Getting Ramdisk init"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/init" -o build/AIK/ramdisk/init && chmod +x build/AIK/ramdisk/init
        fi
    fi

    if ! test -f "build/AIK/ramdisk/fstab.exynos982$SOC"; then
        quotes "Get Fstab for Exynos 982$SOC"
        curl -LSs "${REPO_URL}ramdisk/fstab.exynos982$SOC" -o build/AIK/ramdisk/fstab.exynos982$SOC
    fi
}

setup_dtb_tools() {
    if test -f "build/mkdtimg"; then
        quotes "DTB Build Script Found!"
    else
        quotes "Getting DTB Build Script"
        curl -LSs "${REPO_URL}toolchains/mkdtimg" -o build/mkdtimg && chmod +x build/mkdtimg
    fi

    if ! test -d "build/dtconfigs"; then
        mkdir -p build/dtconfigs
    fi

    if ! test -f "build/dtconfigs/exynos982$SOC.cfg"; then
        quotes "Getting DTB Config for Exynos 982$SOC"
        curl -LSs "${REPO_URL}toolchains/configs/exynos982$SOC.cfg" -o build/dtconfigs/exynos982$SOC.cfg
    fi

    if ! test -f "build/dtconfigs/$MODEL.cfg"; then
        quotes "Getting DTB Config for $MODEL"
        if [[ "$MODEL" == "d1xks" ]]; then
            curl -LSs "${REPO_URL}toolchains/configs/d1x.cfg" -o build/dtconfigs/$MODEL.cfg
        else
            curl -LSs "${REPO_URL}toolchains/configs/$MODEL.cfg" -o build/dtconfigs/$MODEL.cfg
        fi
        [[ "$MODEL" == "d2s" ]] && sed -i "s/d2/$MODEL/g" build/dtconfigs/$MODEL.cfg
    fi
}

detect_env() {
    DATE=`date +"%Y%m%d"`
    BUILD_URL="https://raw.githubusercontent.com/papaL3xa/builds/refs/heads/exynos9820/"
    REPO_URL="https://raw.githubusercontent.com/ivanmeler/android_kernel_samsung_beyondlte/refs/heads/oneui5_beyond/" 
    KERNEL_NAME=BatAxeKernel
    export KBUILD_BUILD_USER=papaL3xa
    export KBUILD_BUILD_HOST=BatAxeKernel

    [[ "$SOC" == "5" ]] && DEVICE=Note10 || DEVICE=S10

    if [ ! -z $RELEASE ]; then
        quotes "Running on GitHub Actions"
        echo BUILD_DEVICE=$DEVICE >> $GITHUB_ENV
    else
        quotes "Running on Local Machine"
        LOCAL=y
    fi

    [[ -z $KERNEL_VERSION ]] && KERNEL_VERSION=Unofficial
    [[ -z $KSU ]] && KSU=y
    [[ -z $CLEAN ]] && CLEAN=n

    setup_aik
    setup_ramdisk
    setup_dtb_tools
    setup_module_files
}

setup_module_files() {
    if ! test -f "build/module-binary"; then
        quotes "Getting Module Binary"
        curl -LSs "https://raw.githubusercontent.com/Zackptg5/MMT-Extended/refs/heads/master/META-INF/com/google/android/update-binary" -o build/module-binary
    fi

    quotes "Getting Module Props"
    curl -LOSs "${BUILD_URL}module.prop" && curl -LOSs "${BUILD_URL}system.prop" && mv *.prop build/

    if ! test -f "build/update-binary"; then
        quotes "Getting Kernel Zip Binary"
        curl -LOSs "${REPO_URL}toolchains/update-binary"
    fi

    quotes "Getting Kernel Zip Script"
    curl -LOSs "${BUILD_URL}updater-script" && mv updater-script build/
}

# =============================================================================
# FUNGSI TOOLCHAIN SETUP
# =============================================================================

setup_neutron_clang() {
    KERNELCLANG=NeutronClang-$NEUTRON
    CLANG_INFO="Neutron Clang ($NEUTRON)"
    TOOLCHAIN_PATH="toolchain/neutron"
    
    quotes "Using $CLANG_INFO"
    
    if test -d "$TOOLCHAIN_PATH"; then
        quotes "$CLANG_INFO Directory Found!"
    else
        rm -rf $TOOLCHAIN_PATH
        mkdir -p $TOOLCHAIN_PATH
        quotes "Downloading $CLANG_INFO"
        cd $TOOLCHAIN_PATH
        wget -q https://github.com/Neutron-Toolchains/neutron-clang/archive/refs/heads/${NEUTRON}.tar.gz
        tar -xf ${NEUTRON}.tar.gz --strip-components=1
        rm -f ${NEUTRON}.tar.gz
        cd $OLDPWD
    fi
    
    setup_clang_environment
}

setup_standard_clang() {
    set_clang_version
    KERNELCLANG=Clang$LLVM
    CLANG_VERSION="r$CLANG"
    CLANG_INFO="Clang $LLVM$MINOR"
    TOOLCHAIN_PATH="toolchain/clang-$CLANG_VERSION"

    quotes "Using $CLANG_INFO"

    if test -d "$TOOLCHAIN_PATH"; then
        quotes "$CLANG_INFO Directory Found!"
    else
        TOOLCHAIN_URL="https://git$HOST.com/$ROM/android_prebuilts_clang_host_linux-x86_clang-$CLANG_VERSION.git"
        quotes "Downloading $CLANG_INFO"
        git clone --depth=1 "$TOOLCHAIN_URL" "$TOOLCHAIN_PATH"
    fi

    setup_clang_environment
}

set_clang_version() {
    case $LLVM in
        12) CLANG=416183b1; MINOR=".0.5"; HOST=hub; ROM="ArrowOS-Devices" ;;
        13) CLANG=433403b; MINOR=".0.3"; HOST=lab; ROM=crdroidandroid ;;
        14) CLANG=450784; MINOR=".0.3"; HOST=lab; ROM=crdroidandroid ;;
        15) CLANG=468909b; MINOR=".0.3"; HOST=lab; ROM=crdroidandroid ;;
        16) CLANG=475365b; MINOR=".0.2"; HOST=lab; ROM=crdroidandroid ;;
        17) CLANG=498229b; MINOR=".0.4"; HOST=lab; ROM=crdroidandroid ;;
        18) CLANG=522817; MINOR=".0.1"; HOST=lab; ROM=crdroidandroid ;;
        19) CLANG=536225; MINOR=".0.1"; HOST=lab; ROM=crdroidandroid ;;
        20) CLANG=547379; MINOR=".0.0"; HOST=lab; ROM=crdroidandroid ;;
        21) CLANG=563880; MINOR=".0.0"; HOST=lab; ROM="reaPeR1010" ;;
        *) LLVM=21; CLANG=563880; MINOR=".0.0"; HOST=lab; ROM="reaPeR1010" ;;
    esac
}

setup_clang_environment() {
    ORIG_PATH=$PATH
    CLANG_DIR="$PWD/$TOOLCHAIN_PATH/bin"
    PATH="$CLANG_DIR:$ORIG_PATH"

    ARGS="
        ARCH=arm64 O=out \
        LLVM=1 LLVM_IAS=1 \
        CC=clang \
        LD=ld.lld \
        AR=llvm-ar \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
    "
}

toolchain() {
    separator
    if [[ "$USE_NEUTRON" == "true" ]]; then
        setup_neutron_clang
    else
        setup_standard_clang
    fi
}

# =============================================================================
# FUNGSI KERNELSU SETUP
# =============================================================================

fix_kernelsu_error() {
    separator
    quotes "Checking KernelSU configuration"
    
    # Remove problematic Kconfig reference if KernelSU not available
    if [[ "$KSU" != "y" ]] || [ ! -f "drivers/kernelsu/Kconfig" ]; then
        quotes "Removing KernelSU Kconfig reference"
        sed -i '/source "drivers\/kernelsu\/Kconfig"/d' drivers/Kconfig 2>/dev/null || true
    fi
}

# =============================================================================
# FUNGSI BUILD KERNEL
# =============================================================================

kernel() {
    separator
    noquotes "Build Information"
    separator
    noquotes "Device: $DEVICE ($MODEL)"
    noquotes "SOC: Exynos 982$SOC"
    noquotes "Defconfig: $KERNEL_DEFCONFIG"
    noquotes "Kernel Version: $KERNEL_VERSION"
    noquotes "Toolchain: $CLANG_INFO"

    # Update kernel version
    sed -i "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/" arch/arm64/configs/$KERNEL_DEFCONFIG
    sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" arch/arm64/configs/$KERNEL_DEFCONFIG

    DEFCONFIG="$KERNEL_DEFCONFIG bataxe.config"
    [[ "$KSU" == "y" ]] && DEFCONFIG="$DEFCONFIG ksu.config"

    separator
    quotes "Generating Configuration"
    make -j$(nproc --all) $ARGS $DEFCONFIG || abort

    separator
    quotes "Building Kernel"
    make -j$(nproc --all) $ARGS || abort

    separator
    quotes "Kernel Build Complete!"
    
    # Prepare output
    rm -rf build/out/$MODEL
    mkdir -p build/out/$MODEL
}

# =============================================================================
# FUNGSI BUILD DTB/DTBO
# =============================================================================

dtb() {
    quotes "Building DTB/DTBO Images"
    ./build/mkdtimg cfg_create build/out/$MODEL/dtb_exynos982$SOC.img build/dtconfigs/exynos982$SOC.cfg -d out/arch/arm64/boot/dts/exynos
    ./build/mkdtimg cfg_create build/out/$MODEL/dtbo_$MODEL.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung
}

# =============================================================================
# FUNGSI BUILD RAMDISK
# =============================================================================

ramdisk() {
    separator
    quotes "Building Boot Image"
    
    # Clean AIK directory
    rm -rf build/AIK/split_img build/AIK/ramdisk-new.cpio.gz build/AIK/image-new.img
    mkdir -p build/AIK/split_img
    
    # Copy kernel image
    cp out/arch/arm64/boot/Image build/AIK/split_img/kernel
    
    # Create boot image
    cd build/AIK
    ./repackimg.sh --original
    cd ../..
    
    check "Boot Image"
}

# =============================================================================
# FUNGSI BUILD FLASHABLE ZIP
# =============================================================================

build_zip() {
    separator
    quotes "Creating Flashable Zip"
    
    # Prepare zip structure
    rm -rf build/out/$MODEL/zip
    mkdir -p build/export
    mkdir -p build/out/$MODEL/zip/META-INF/com/google/android
    
    # Copy files
    cp build/AIK/image-new.img build/out/$MODEL/zip/boot.img
    cp build/out/$MODEL/dtb_exynos982$SOC.img build/out/$MODEL/zip/dtb.img
    cp build/out/$MODEL/dtbo_$MODEL.img build/out/$MODEL/zip/dtbo.img
    cp build/update-binary build/out/$MODEL/zip/META-INF/com/google/android/
    cp build/updater-script build/out/$MODEL/zip/META-INF/com/google/android/
    
    # Update updater script with build info
    sed -i "s/Kernel Version: /Kernel Version: $KERNEL_VERSION/g" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    sed -i "s/Device: /Device: $DEVICE ($MODEL)/g" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    
    # Create zip
    cd build/out/$MODEL/zip
    zip -r9 ../$KERNEL_NAME-$KERNEL_VERSION-$MODEL-$DATE.zip .
    cd ../../..
    mv build/out/$MODEL/$KERNEL_NAME-$KERNEL_VERSION-$MODEL-$DATE.zip build/export/
    
    quotes "Zip created: build/export/$KERNEL_NAME-$KERNEL_VERSION-$MODEL-$DATE.zip"
}

# =============================================================================
# FUNGSI PARSING ARGUMEN
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [options]
Options:
    -m, --model MODEL      Device model (d2s, d1, d2x, etc) - default: d2s
    -k, --ksu [y/N]        Include KernelSU - default: y
    -v, --ver VERSION      Kernel version - default: Unofficial
    -l, --llvm VERSION     Clang version (12-21) or Neutron date - default: 21
    -c, --clean [y/N]      Clean build - default: n
    -h, --help             Show this help
EOF
}

parse_arguments() {
    USE_NEUTRON=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--model) MODEL="$2"; shift 2 ;;
            -k|--ksu) KSU="$2"; shift 2 ;;
            -v|--ver) KERNEL_VERSION="$2"; shift 2 ;;
            -l|--llvm) 
                if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -ge 12 ]] && [[ "$2" -le 21 ]]; then
                    LLVM="$2"
                    USE_NEUTRON=false
                else
                    NEUTRON="${2:-10032024}"
                    USE_NEUTRON=true
                fi
                shift 2
                ;;
            -c|--clean) CLEAN="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

setup_model() {
    [[ -z $MODEL ]] && MODEL=d2s
    
    KERNEL_DEFCONFIG=bataxe-"$MODEL"_defconfig
    case $MODEL in
        beyond0lte) SOC=0; BOARD=SRPRI28A014KU ;;
        beyond1lte) SOC=0; BOARD=SRPRI28B014KU ;;
        beyond2lte) SOC=0; BOARD=SRPRI17C014KU ;;
        beyondx) SOC=0; BOARD=SRPSC04B011KU ;;
        d1) SOC=5; BOARD=SRPSD26B007KU ;;
        d1xks) SOC=5; BOARD=SRPSD23A002KU ;;
        d2s) SOC=5; BOARD=SRPSC14B007KU ;;
        d2x) SOC=5; BOARD=SRPSC14C007KU ;;
        *) echo "Unknown model: $MODEL"; usage; exit 1 ;;
    esac
}

# =============================================================================
# FUNGSI MAIN
# =============================================================================

main() {
    START_TIME=$(date +%s)
    
    echo "========================================================="
    echo "           BATAXE KERNEL BUILD SCRIPT"
    echo "========================================================="
    
    parse_arguments "$@"
    setup_model
    detect_env
    toolchain
    fix_kernelsu_error
    
    pushd $(dirname "$0") > /dev/null
    
    kernel
    dtb
    ramdisk
    build_zip
    
    if [[ "$LOCAL" == "y" ]]; then
        clean
    fi
    
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    quotes "Build completed in $(($ELAPSED / 60))m $(($ELAPSED % 60))s"
    
    popd > /dev/null
}

main "$@"