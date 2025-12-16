#!/bin/bash

# =============================================================================
# KERNEL BUILD SCRIPT FOR EXYNOS 9820 DEVICES
# Script ini digunakan untuk mengkompilasi kernel Android untuk perangkat Samsung Exynos 9820
# =============================================================================

# =============================================================================
# FUNGSI UTILITY
# =============================================================================

# Fungsi untuk menampilkan separator/pembatas
separator() {
    echo "---------------------------------------------------------"
}

# Fungsi untuk menampilkan pesan dengan format quotes
quotes() {
    echo "-- $1..."
}

# Fungsi untuk menampilkan pesan tanpa format quotes
noquotes() {
    echo "-- $1"
}

# =============================================================================
# FUNGSI CLEANUP
# =============================================================================

clean() {
    separator
    quotes "Cleanup Build Files"

    # Menghapus file build dan konfigurasi sementara
    rm -rf o* .w* build/AIK/s* build/AIK/ramdisk/f* build/*.p* build/*er* arch/arm64/configs/k* && git restore arch/arm64/configs/$KERNEL_DEFCONFIG

    # Jika opsi clean diaktifkan, reset semua perubahan ke commit terakhir
    if [[ "$CLEAN" == "y" ]]; then
        separator
        quotes "Revert all Change to Latest Commit (All Uncommit Change will Lost!)"
        separator
        rm -rf K* toolc* build/A* build/d* build/m* build/s* build/u* && git clean -df && git reset --hard HEAD
    fi
}

# =============================================================================
# FUNGSI ERROR HANDLING
# =============================================================================

abort() {
    # Kembali ke direktori sebelumnya
    cd -

    # Jika running di local machine, lakukan cleanup
    if [[ "$LOCAL" == "y" ]]; then
        clean
    fi

    separator
    quotes "Failed to Compile Kernel! Exiting"
    separator

    exit -1
}

# Fungsi untuk mengecek status eksekusi perintah sebelumnya
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

# Fungsi untuk update submodules
submodule() {
    separator
    quotes "Fetch all Submodules Update"

    git submodule init && git submodule update --remote
    git submodule update -f -q --init --recursive > /dev/null
    check "Submodules"
}

# Fungsi untuk mendeteksi dan setup environment build
detect_env() {
    # Set Build Variable
    separator

    DATE=`date +"%Y%m%d"`
    BUILD_URL="https://raw.githubusercontent.com/papaL3xa/builds/refs/heads/exynos9820/"
    REPO_URL="https://raw.githubusercontent.com/ivanmeler/android_kernel_samsung_beyondlte/refs/heads/oneui5_beyond/" 
    KERNEL_NAME=BatAxeKernel
    export KBUILD_BUILD_USER=papaL3xa
    export KBUILD_BUILD_HOST=BatAxeKernel

    # Tentukan device berdasarkan SOC
    if [[ "$SOC" == "5" ]]; then
        DEVICE=Note10
    else
        DEVICE=S10
    fi

    # Cek apakah running di GitHub Actions atau local
    if [[ "$RELEASE" == "y" ]]; then
        quotes "Running in Release Mode"
        # Untuk GitHub Actions, gunakan GITHUB_ENV jika tersedia
        if [ ! -z "$GITHUB_ENV" ]; then
            echo BUILD_DEVICE=$DEVICE >> $GITHUB_ENV
        fi
    elif [[ "$RELEASE" == "n" ]]; then
        quotes "Running in CI Mode"
    else
        quotes "Running on Local Machine"
        LOCAL=y
    fi

    # Set default value untuk variabel yang tidak ditentukan
    if [ -z "$KERNEL_VERSION" ]; then
        KERNEL_VERSION=Unofficial
    fi

    if [ -z "$KSU" ]; then
        KSU=y
    fi

    if [ -z "$CLEAN" ]; then
        CLEAN=n
    fi

    if [ -z "$RELEASE" ]; then
        RELEASE=n
    fi

    separator

    # Setup Android Image Kitchen
    if test -d "build/AIK"; then
        quotes "Android Image Kitchen Directory Found!"
    else
        quotes "Add Android Image Kitchen as Submodule"
        git submodule add -f -q https://github.com/papaL3xa/Android-Image-Kitchen build/AIK > /dev/null && chmod +x build/AIK/mk*
        check "Android Image Kitchen Directory"
    fi

    # Setup ramdisk binary
    setup_ramdisk

    # Setup DTB build tools
    setup_dtb_tools

    # Setup module binary dan props
    setup_module_files

    check "Build Environment"
}

# Fungsi untuk setup ramdisk binary
setup_ramdisk() {
    if test -f "build/AIK/ramdisk/dpolicy" && test -f "build/AIK/init"; then
        quotes "Ramdisk Binary Found!"
    else
        if ! test -d "build/AIK/ramdisk"; then
            mkdir -p build/AIK/ramdisk
        fi
        
        if ! test -f "build/AIK/dpolicy"; then
            quotes "Getting Ramdisk dpolicy"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/dpolicy" -o build/AIK/ramdisk/dpolicy
        fi

        if ! test -f "build/AIK/init"; then
            quotes "Getting Ramdisk init"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/init" -o build/AIK/ramdisk/init && chmod +x build/AIK/ramdisk/i*
        fi

        check "Ramdisk Binary"
    fi

    if ! test -f "build/AIK/fstab.exynos982$SOC"; then
        quotes "Get Fstab for Exynos 982$SOC"
        rm -rf build/AIK/ramdisk/f*
        curl -LSs "${REPO_URL}ramdisk/fstab.exynos982$SOC" -o build/AIK/ramdisk/fstab.exynos982$SOC
        check "Fstab for Exynos 982$SOC"
    fi
}

# Fungsi untuk setup DTB build tools
setup_dtb_tools() {
    if test -f "build/mkdtimg"; then
        quotes "DTB Build Script Found!"
    else
        quotes "Getting DTB Build Script"
        curl -LSs "${REPO_URL}toolchains/mkdtimg" -o build/mkdtimg && chmod +x build/mk*
        check "DTB Build Script"
    fi

    if test -f "build/dtconfigs/exynos982$SOC.cfg" && test -f "build/dtconfigs/$MODEL.cfg"; then
        quotes "DTB Config Directory Found!"
    else
        if ! test -d "build/dtconfigs"; then
            mkdir -p build/dtconfigs
        fi

        download_dtb_configs
        check "DTB Config Directory"
    fi
}

# Fungsi untuk download DTB configs
download_dtb_configs() {
    if ! test -f "build/dtconfigs/exynos982$SOC.cfg"; then
        quotes "Getting DTB Config for Exynos 982$SOC"
        curl -LSs "${REPO_URL}toolchains/configs/exynos982$SOC.cfg" -o build/dtconfigs/exynos982$SOC.cfg
    fi

    if ! test -f "build/dtconfigs/$MODEL.cfg"; then
        quotes "Getting DTB Config for $DEVICE ($MODEL)"

        if [[ "$MODEL" == "d1xks" ]]; then
            curl -LSs "${REPO_URL}toolchains/configs/d1x.cfg" -o build/dtconfigs/$MODEL.cfg
        else
            curl -LSs "${REPO_URL}toolchains/configs/$MODEL.cfg" -o build/dtconfigs/$MODEL.cfg
        fi

        # Patch untuk model d2s
        if [[ "$MODEL" == "d2s" ]]; then
            sed -i "s/d2/$MODEL/g" build/dtconfigs/$MODEL.cfg
        fi
    fi
}

# Fungsi untuk setup module files
setup_module_files() {
    if ! test -f "build/module-binary"; then
        quotes "Getting Module Binary"
        curl -LSs "https://raw.githubusercontent.com/Zackptg5/MMT-Extended/refs/heads/master/META-INF/com/google/android/update-binary" -o build/module-binary
        check "Module Binary"
    fi

    quotes "Getting Module Props"
    curl -LOSs "${BUILD_URL}module.prop" && curl -LOSs "${BUILD_URL}system.prop" && mv *.p* build
    check "Module Props"

    if ! test -f "build/update-binary"; then
        quotes "Getting Kernel Zip Binary"
        curl -LOSs "${REPO_URL}toolchains/update-binary"
        check "Kernel Zip Binary"
    fi

    quotes "Getting Kernel Zip Script"
    curl -LOSs "${BUILD_URL}updater-script" && mv up* build
    check "Kernel Zip Script"
}

# =============================================================================
# FUNGSI TOOLCHAIN SETUP
# =============================================================================

toolchain() {
    separator
    if [[ "$USE_NEUTRON" == "true" ]]; then
        setup_neutron_clang
    else
        setup_standard_clang
    fi
}

# Fungsi untuk setup Neutron Clang
setup_neutron_clang() {
    NEUTRON_DATE="=$NEUTRON"
    KERNELCLANG=NeutronClang-$NEUTRON
    CLANG_INFO="Neutron Clang ($NEUTRON)"
    TOOLCHAIN_PATH="toolchain/neutron-$NEUTRON"
    
    quotes "Using $CLANG_INFO"
    
    if test -d "$TOOLCHAIN_PATH"; then
        quotes "$CLANG_INFO Directory Found!"
    else
        rm -rf $TOOLCHAIN_PATH
        mkdir -p $TOOLCHAIN_PATH
        quotes "Downloading $CLANG_INFO"
        separator
        cd $TOOLCHAIN_PATH
        bash <(curl -LSs "https://raw.githubusercontent.com/Neutron-Toolchains/antman/refs/heads/main/antman") -S$NEUTRON_DATE
        
        # Install file package jika belum ada
        if ! test -f "/usr/bin/file"; then
            separator
            quotes "Installing File Package"
            separator
            sudo apt install -y file
        fi
        
        separator
        quotes "Patching glibc"
        separator
        bash <(curl -LSs "https://raw.githubusercontent.com/Neutron-Toolchains/antman/refs/heads/main/antman") --patch=glibc
        cd $OLDPWD
        separator
        check "Neutron Clang"
    fi
    
    setup_clang_environment
}

# Fungsi untuk setup standard Clang
setup_standard_clang() {
    set_clang_version
    KERNELCLANG=Clang$LLVM
    CLANG_VERSION="r$CLANG"
    CLANG_INFO="Clang $LLVM$MINOR (Based on $CLANG_VERSION)"
    TOOLCHAIN_PATH="toolchain/clang-$CLANG_VERSION"

    quotes "Using $CLANG_INFO"

    if test -d "$TOOLCHAIN_PATH"; then
        quotes "$CLANG_INFO Directory Found!"
    else
        TOOLCHAIN_URL="https://git$HOST.com/$ROM/android_prebuilts_clang_host_linux-x86_clang-$CLANG_VERSION.git"

        quotes "Downloading $CLANG_INFO"
        git submodule add -f -q "$TOOLCHAIN_URL" "$TOOLCHAIN_PATH" > /dev/null
        check "clang-$CLANG_VERSION"
    fi

    setup_clang_environment
}

# Fungsi untuk set versi Clang berdasarkan pilihan LLVM
set_clang_version() {
    case $LLVM in
        12)
            CLANG=416183b1 # Clang 12.0.7
            MINOR=".0.5"
            HOST=hub
            ROM="ArrowOS-Devices"
            ;;
        13)
            CLANG=433403b # Clang 13.0.3
            MINOR=".0.3"
            HOST=lab
            ROM=crdroidandroid
            ;;
        14)
            CLANG=450784 # Clang 14.0.3
            MINOR=".0.3"
            HOST=lab
            ROM=crdroidandroid
            ;;
        15)
            CLANG=468909b # Clang 15.0.3
            MINOR=".0.3"
            HOST=lab
            ROM=crdroidandroid
            ;;
        16)
            CLANG=475365b # Clang 16.0.2
            MINOR=".0.2"
            HOST=lab
            ROM=crdroidandroid
            ;;
        17)
            CLANG=498229b # Clang 17.0.4
            MINOR=".0.4"
            HOST=lab
            ROM=crdroidandroid
            ;;
        18)
            CLANG=522817 # Clang 18.0.1
            MINOR=".0.1"
            HOST=lab
            ROM=crdroidandroid
            ;;
        19)
            CLANG=536225 # Clang 19.0.1
            MINOR=".0.1"
            HOST=lab
            ROM=crdroidandroid
            ;;
        20)
            CLANG=547379 # Clang 20.0.0
            MINOR=".0.0"
            HOST=lab
            ROM=crdroidandroid
            ;;
        21)
            CLANG=563880 # Clang 21.0.0
            MINOR=".0.0"
            HOST=lab
            ROM="reaPeR1010"
            ;;
        *)
            LLVM=21
            CLANG=563880 # Clang 21.0.0
            MINOR=".0.0"
            HOST=lab
            ROM="reaPeR1010"
            ;;
    esac
}

# Fungsi untuk setup environment Clang
setup_clang_environment() {
    ORIG_PATH=$PATH
    CLANG_DIR="$PWD/$TOOLCHAIN_PATH"
    PATH="$CLANG_DIR/bin:$ORIG_PATH"

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
        READELF=llvm-readelf \
        OBJSIZE=llvm-size \
    "
}

# =============================================================================
# FUNGSI KERNELSU SETUP
# =============================================================================

kernelsu() {
    separator

    # Setup KernelSU Next
    if ! test -d "drivers/kernelsu"; then
        quotes "Update KernelSU Next as Submodule"
        separator
        git submodule init && git submodule update --remote
    fi
}

# =============================================================================
# FUNGSI BUILD KERNEL
# =============================================================================

kernel() {
    # Build Kernel Image
    separator
    noquotes "Fetch Kernel Info"
    separator
    noquotes "Device: $DEVICE ("$MODEL")"
    noquotes "SOC: Exynos 982$SOC"
    noquotes "Defconfig: $KERNEL_DEFCONFIG"
    noquotes "Kernel Version: $KERNEL_VERSION"
    noquotes "Build Date: `date +"%Y-%m-%d"`"

    if [ -z "$KSU_NEXT" ]; then
        noquotes "KernelSU Next with SuSFS: Not Include"
    else
        noquotes "KernelSU Next with SuSFS: Include (Using $KSU_NEXT)"
    fi

    # Update kernel configuration
    update_kernel_config

    DEFCONFIG="$KERNEL_DEFCONFIG bataxe.config $KSU_NEXT"

    separator
    noquotes "Building Kernel Using $KERNEL_DEFCONFIG"
    quotes "Generating Configuration Files"
    separator

    make -j$(nproc --all) $ARGS $DEFCONFIG || abort

    separator
    quotes "Building Kernel"
    separator

    make -j$(nproc --all) $ARGS || abort

    separator
    quotes "Finished Kernel Build!"
    separator

    # Prepare output directory
    rm -rf build/out/$MODEL
    mkdir -p build/out/$MODEL
}

# Fungsi untuk update konfigurasi kernel
update_kernel_config() {
    sed -i "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/" arch/arm64/configs/$KERNEL_DEFCONFIG
    sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" arch/arm64/configs/$KERNEL_DEFCONFIG
}

# =============================================================================
# FUNGSI BUILD DTB/DTBO
# =============================================================================

dtb() {
    # Build DTB Image
    quotes "Building Device Tree Blob Image for Exynos 982$SOC"
    separator

    ./build/mkdtimg cfg_create build/out/$MODEL/dtb_exynos982$SOC.img build/dtconfigs/exynos982$SOC.cfg -d out/arch/arm64/boot/dts/exynos

    # Build DTBO Image
    separator
    quotes "Building Device Tree Blob Image for $DEVICE ($MODEL)"
    separator

    ./build/mkdtimg cfg_create build/out/$MODEL/dtbo_$MODEL.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung
}

# =============================================================================
# FUNGSI BUILD RAMDISK
# =============================================================================

ramdisk() {
    # Build Ramdisk
    separator
    quotes "Building Ramdisk"
    separator

    rm -rf build/AIK/s*
    mkdir -p build/AIK/split_img
    pushd build/AIK/split_img > /dev/null
    
    # Setup boot image components
    setup_boot_image_components
    
    popd > /dev/null

    # Create Boot Image
    quotes "Calling Android Image Kitchen"
    pushd build/AIK > /dev/null

    # Create ramdisk directories
    create_ramdisk_directories

    ./mkimg
    popd > /dev/null
}

# Fungsi untuk setup komponen boot image
setup_boot_image_components() {
    mv ../../../out/arch/arm64/boot/Image boot.img-kernel
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
}

# Fungsi untuk membuat direktori ramdisk
create_ramdisk_directories() {
    mkdir -p ramdisk/debug_ramdisk
    mkdir -p ramdisk/dev
    mkdir -p ramdisk/mnt
    mkdir -p ramdisk/proc
    mkdir -p ramdisk/sys
}

# =============================================================================
# FUNGSI BUILD FLASHABLE ZIP
# =============================================================================

build_zip() {
    # Build Zip
    separator
    quotes "Building Zip"
    if [[ "$LOCAL" == "y" ]] || [[ "$RELEASE" == "y" ]]; then
        separator
    fi

    pushd build > /dev/null
    
    # Prepare zip structure
    prepare_zip_structure
    
    # Copy files to zip directory
    copy_files_to_zip
    
    # Create module zip
    create_module_zip
    
    popd > /dev/null
    
    # Update updater script dengan informasi build
    update_updater_script
    
    # Create final zip
    create_final_zip
}

# Fungsi untuk mempersiapkan struktur zip
prepare_zip_structure() {
    rm -rf out/$MODEL/zip
    mkdir -p export
    mkdir -p out/$MODEL/zip/module/common/
    mkdir -p out/$MODEL/zip/module/META-INF/com/google/android
    mkdir -p out/$MODEL/zip/META-INF/com/google/android
    mv AIK/image-new.img out/$MODEL/boot-patched.img
}

# Fungsi untuk menyalin file ke direktori zip
copy_files_to_zip() {
    cp out/$MODEL/boot-patched.img out/$MODEL/zip/boot.img
    cp out/$MODEL/dtb_exynos982$SOC.img out/$MODEL/zip/dtb.img
    cp out/$MODEL/dtbo_$MODEL.img out/$MODEL/zip/dtbo.img
    cp update-binary out/$MODEL/zip/META-INF/com/google/android/
    mv updater-script out/$MODEL/zip/META-INF/com/google/android/

    mv module.prop out/$MODEL/zip/module/
    mv system.prop out/$MODEL/zip/module/common/
    cp module-binary out/$MODEL/zip/module/META-INF/com/google/android/update-binary
    echo -e "#MAGISK" > out/$MODEL/zip/module/META-INF/com/google/android/updater-script
}

# Fungsi untuk membuat module zip
create_module_zip() {
    cd out/$MODEL/zip/module
    zip -r ../module.zip .
    rm -rf out/$MODEL/zip/module
}

# Fungsi untuk update updater script dengan informasi build
update_updater_script() {
    sed -i "s/ui_print(\" Kernel Version: \");/ui_print(\" Kernel Version: $KERNEL_VERSION\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    sed -i "s/ui_print(\" Kernel Device: \");/ui_print(\" Kernel Device: $DEVICE ($MODEL)\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    sed -i "s/ui_print(\" Kernel Toolchain: \");/ui_print(\" Kernel Toolchain: $CLANG_INFO\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
}

# Fungsi untuk membuat final zip
create_final_zip() {
    if [[ "$LOCAL" == "y" ]] || [[ "$RELEASE" == "y" ]]; then
        sed -i "s/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-"$DEVICE"-$MODEL\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-"$DATE"-"$DEVICE"-$MODEL-$KERNELCLANG\"/" arch/arm64/configs/$KERNEL_DEFCONFIG
        NAME=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/$KERNEL_DEFCONFIG | cut -d '"' -f 2)
        NAME=${NAME:1}.zip
        pushd build/out/$MODEL/zip > /dev/null
        zip -r ../"$NAME" .
        popd > /dev/null
        pushd build/out > /dev/null
        rm -rf $MODEL/zip
        mv $MODEL/"$NAME" ../export/"$NAME"
        popd > /dev/null
    fi
}

# =============================================================================
# FUNGSI PARSING ARGUMEN
# =============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the Model Code of the Phone (default: d2s)
                           Available models: beyond0lte, beyond1lte, beyond2lte, beyondx, d1, d1xks, d2s, d2x
    -k, --ksu [y/N]        Include KernelSU Next with SuSFS (default: y)
    -v, --ver [value]      Kernel version (default: Unofficial)
    -r, --rel [y/N]        Release mode: y for Release, n for CI (default: n)
    -c, --clean [y/N]      Reset all changes to latest commit (default: n)
                           WARNING: All uncommitted changes will be lost!
    -l, --llvm [value]     Clang version (12-21) or Neutron Clang version (default: 21)
                           Examples: 18 for Clang 18, 10032024 for Neutron Clang
    -h, --help             Show this help message

Examples:
    ./build.sh -m d2s -r y              # Build for d2s model in Release mode
    ./build.sh -m beyond2lte -r n       # Build for beyond2lte in CI mode
    ./build.sh -m d1xks -k n -l 18      # Build for d1xks without KSU, using Clang 18
    ./build.sh -m d2s -c y              # Clean build for d2s
EOF
}

# Fungsi untuk parsing argumen command line
parse_arguments() {
    USE_NEUTRON=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model|-m)
                if [[ -n "$2" && "$2" != -* ]]; then
                    MODEL="$2"
                    shift 2
                else
                    echo "Error: --model requires a value"
                    usage
                    exit 1
                fi
                ;;
            --ksu|-k)
                if [[ -n "$2" && "$2" != -* ]]; then
                    KSU="$2"
                    shift 2
                else
                    echo "Error: --ksu requires a value (y/N)"
                    usage
                    exit 1
                fi
                ;;
            --ver|-v)
                if [[ -n "$2" && "$2" != -* ]]; then
                    KERNEL_VERSION="$2"
                    shift 2
                else
                    echo "Error: --ver requires a value"
                    usage
                    exit 1
                fi
                ;;
            --rel|-r)
                if [[ -n "$2" && "$2" != -* ]]; then
                    RELEASE="$2"
                    shift 2
                else
                    echo "Error: --rel requires a value (y/N)"
                    usage
                    exit 1
                fi
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --clean|-c)
                if [[ -n "$2" && "$2" != -* ]]; then
                    CLEAN="$2"
                    shift 2
                else
                    echo "Error: --clean requires a value (y/N)"
                    usage
                    exit 1
                fi
                ;;
            --llvm|-l)
                if [[ -n "$2" && "$2" != -* ]]; then
                    LLVM="$2"
                    shift 2
                else
                    LLVM=21
                    shift
                fi
                
                # Check if LLVM version is between 12-21
                if [[ "$LLVM" -ge 12 ]] && [[ "$LLVM" -le 21 ]]; then
                    USE_NEUTRON=false
                    echo "-- Using Clang $LLVM"
                else
                    USE_NEUTRON=true
                    NEUTRON="${LLVM:-10032024}"
                    echo "-- Using Neutron Clang ($NEUTRON)"
                fi
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Fungsi untuk setup model dan SOC
setup_model() {
    if [ -z "$MODEL" ]; then
        MODEL=d2s
        echo "-- Using default model: $MODEL"
    fi

    KERNEL_DEFCONFIG=bataxe-"$MODEL"_defconfig
    case $MODEL in
    beyond0lte)
        SOC=0
        BOARD=SRPRI28A014KU
        ;;
    beyond1lte)
        SOC=0
        BOARD=SRPRI28B014KU
        ;;
    beyond2lte)
        SOC=0
        BOARD=SRPRI17C014KU
        ;;
    beyondx)
        SOC=0
        BOARD=SRPSC04B011KU
        ;;
    d1)
        SOC=5
        BOARD=SRPSD26B007KU
        ;;
    d1xks)
        SOC=5
        BOARD=SRPSD23A002KU
        ;;
    d2s)
        SOC=5
        BOARD=SRPSC14B007KU
        ;;
    d2x)
        SOC=5
        BOARD=SRPSC14C007KU
        ;;
    *)
        echo "Error: Unknown model: $MODEL"
        echo "Available models: beyond0lte, beyond1lte, beyond2lte, beyondx, d1, d1xks, d2s, d2x"
        usage
        exit 1
        ;;
    esac
}

# =============================================================================
# FUNGSI MAIN
# =============================================================================

main() {
    # Setup logging
    rm -rf ./build.log
    
    (
        START=`date +%s`

        separator
        quotes "Preparing Build Environment"

        # Parse arguments dan setup environment
        parse_arguments "$@"
        setup_model
        detect_env
        toolchain
        
        # Change to script directory
        pushd $(dirname "$0") > /dev/null

        # Setup submodules jika running di local
        if [[ "$LOCAL" == "y" ]]; then
            submodule
        fi

        # Setup KernelSU jika diaktifkan
        if [[ "$KSU" == "y" ]]; then
            KSU_NEXT=ksu.config
            kernelsu
        fi

        # Build process
        kernel
        dtb
        ramdisk
        build_zip

        # Cleanup jika running di local
        if [[ "$LOCAL" == "y" ]]; then
            clean
            separator
        fi

        # Calculate and display build time
        END=`date +%s`
        let "ELAPSED=$END-$START"
        quotes "Total Compile Time was $(($ELAPSED / 60)) Minutes and $(($ELAPSED % 60)) Seconds"
        separator
        
    ) 2>&1 | tee -a ./build.log
}

# =============================================================================
# EXECUTE MAIN FUNCTION
# =============================================================================

main "$@"