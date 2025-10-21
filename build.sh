#!/bin/bash

set -e

separator ()
{
  echo "---------------------------------------------------------"
}

quotes () 
{
  echo "-- $1..."
}

noquotes () 
{
  echo "-- $1"
}

clean ()
{
    separator
    quotes "Cleanup Build Files"

    rm -rf o* .w* build/AIK/s* build/AIK/ramdisk/f* build/*.p* build/*er* arch/arm64/configs/k* && git restore arch/arm64/configs/$KERNEL_DEFCONFIG

    if [[ "$CLEAN" == "y" ]]; then
        separator
        quotes "Revert all Change to Latest Commit (All Uncommit Change will Lost!)"
        separator
        rm -rf K* toolc* build/A* build/d* build/m* build/s* build/u* && git clean -df && git reset --hard HEAD
    fi
}

abort ()
{
    cd -

    if [[ "$LOCAL" == "y" ]]; then
        clean
    fi

    separator
    quotes "Failed to Compile Kernel! Exiting"
    separator

    exit -1
}

check () 
{
    if [ $? -eq 0 ]; then
        echo "-- Setup $1 Done!"
    else
        quotes "Failed! Cancel the Script"
        abort
    fi
}

usage ()
{
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the Model Code of the Phone (default: d2s)
    -k, --ksu [y/N]        Include KernelSU Next with SuSFS (default: y)
    -v, --version [value]  Kernel Version (default: Unofficial)
    -r, --release [y/N]    Release Type (y: Release - n: CI) (default: n)
    -c, --clean [y/N]      Reset all Change to Latest Commit [!! Your Uncommit Change will Lost !!] (default: n)
    -l, --llvm [value]     Clang (12-21) or Neutron Clang Version (default: 10032024)
    -h, --help             List all Build Script Command
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU="$2"
            shift 2
            ;;
        --version|-v)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        --release|-r)
            RELEASE="$2"
            shift 2
            ;;
        --clean|-c)
            CLEAN="$2"
            shift 2
            ;;
        --llvm|-l)
            if [[ -n "$2" && "$2" != -* ]]; then
                if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -ge 12 ]] && [[ "$2" -le 21 ]]; then
                    LLVM="$2"
                    USE_NEUTRON=false
                else
                    NEUTRON="$2"
                    USE_NEUTRON=true
                fi
                shift 2
            else
                NEUTRON=10032024
                USE_NEUTRON=true
                shift
            fi
            ;;
        --help|-h)
            usage
            exit 1
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values
if [ -z "$MODEL" ]; then
    MODEL=d2s
fi

if [ -z "$KSU" ]; then
    KSU=y
fi

if [ -z "$KERNEL_VERSION" ]; then
    KERNEL_VERSION=Unofficial
fi

if [ -z "$RELEASE" ]; then
    RELEASE=n
fi

if [ -z "$CLEAN" ]; then
    CLEAN=n
fi

if [ -z "$USE_NEUTRON" ]; then
    USE_NEUTRON=false
    LLVM=21
fi

# Set device-specific variables
KERNEL_DEFCONFIG=bataxe-"$MODEL"_defconfig
case $MODEL in
beyond0lte)
    SOC=0
    BOARD=SRPRI28A014KU
    DEVICE=S10
;;
beyond1lte)
    SOC=0
    BOARD=SRPRI28B014KU
    DEVICE=S10
;;
beyond2lte)
    SOC=0
    BOARD=SRPRI17C014KU
    DEVICE=S10
;;
beyondx)
    SOC=0
    BOARD=SRPSC04B011KU
    DEVICE=S10
;;
d1)
    SOC=5
    BOARD=SRPSD26B007KU
    DEVICE=Note10
;;
d1xks)
    SOC=5
    BOARD=SRPSD23A002KU
    DEVICE=Note10
;;
d2s)
    SOC=5
    BOARD=SRPSC14B007KU
    DEVICE=Note10
;;
d2x)
    SOC=5
    BOARD=SRPSC14C007KU
    DEVICE=Note10
;;
*)
    echo "Unknown model: $MODEL"
    usage
    exit 1
esac

# Export variables for GitHub Actions
if [ ! -z "$GITHUB_ENV" ]; then
    echo "BUILD_DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "SOC=$SOC" >> $GITHUB_ENV
    echo "BOARD=$BOARD" >> $GITHUB_ENV
    echo "KERNEL_DEFCONFIG=$KERNEL_DEFCONFIG" >> $GITHUB_ENV
    echo "MODEL=$MODEL" >> $GITHUB_ENV
fi

detect_env ()
{
    # Set Build Variable
    separator

    DATE=`date +"%Y%m%d"`
    BUILD_URL="https://raw.githubusercontent.com/papaL3xa/builds/refs/heads/exynos9820/"
    REPO_URL="https://raw.githubusercontent.com/ivanmeler/android_kernel_samsung_beyondlte/refs/heads/oneui5_beyond/" 
    KERNEL_NAME=BatAxeKernel
    export KBUILD_BUILD_USER=papaL3xa
    export KBUILD_BUILD_HOST=BatAxeKernel

    if [ ! -z "$RELEASE" ] && [ "$RELEASE" = "y" ]; then
        quotes "Running on GitHub Actions - Release Mode"
    elif [ ! -z "$GITHUB_ACTIONS" ]; then
        quotes "Running on GitHub Actions - CI Mode"
    else
        quotes "Running on Local Machine"
        LOCAL=y
    fi

    separator

    if test -d "build/AIK"; then
        quotes "Android Image Kitchen Directory Found!"
    else
        quotes "Add Android Image Kitchen as Submodule"
        git submodule add -f -q https://github.com/papaL3xa/Android-Image-Kitchen build/AIK > /dev/null && chmod +x build/AIK/mk*
        check "Android Image Kitchen Directory"
    fi

    if test -f "build/AIK/ramdisk/dpolicy" && test -f "build/AIK/ramdisk/init"; then
        quotes "Ramdisk Binary Found!"
    else
        if ! test -d "build/AIK/ramdisk"; then
            mkdir -p build/AIK/ramdisk
        fi
        
        if ! test -f "build/AIK/ramdisk/dpolicy"; then
            quotes "Getting Ramdisk dpolicy"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/dpolicy" -o build/AIK/ramdisk/dpolicy
        fi

        if ! test -f "build/AIK/ramdisk/init"; then
            quotes "Getting Ramdisk init"
            curl -LSs "${REPO_URL}ramdisk/ramdisk/init" -o build/AIK/ramdisk/init && chmod +x build/AIK/ramdisk/init
        fi

        check "Ramdisk Binary"
    fi

    if ! test -f "build/AIK/ramdisk/fstab.exynos982$SOC"; then
        quotes "Get Fstab for Exynos 982$SOC"
        rm -rf build/AIK/ramdisk/f*
        curl -LSs "${REPO_URL}ramdisk/fstab.exynos982$SOC" -o build/AIK/ramdisk/fstab.exynos982$SOC
        check "Fstab for Exynos 982$SOC"
    fi

    if test -f "build/mkdtimg"; then
        quotes "DTB Build Script Found!"
    else
        quotes "Getting DTB Build Script"
        curl -LSs "${REPO_URL}toolchains/mkdtimg" -o build/mkdtimg && chmod +x build/mkdtimg
        check "DTB Build Script"
    fi

    if test -f "build/dtconfigs/exynos982$SOC.cfg" && test -f "build/dtconfigs/$MODEL.cfg"; then
        quotes "DTB Config Directory Found!"
    else
        if ! test -d "build/dtconfigs"; then
            mkdir -p build/dtconfigs
        fi

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

            if [[ "$MODEL" == "d2s" ]]; then
                sed -i "s/d2/$MODEL/g" build/dtconfigs/$MODEL.cfg
            fi
        fi

        check "DTB Config Directory"
    fi

    if ! test -f "build/module-binary"; then
        quotes "Getting Module Binary"
        curl -LSs "https://raw.githubusercontent.com/Zackptg5/MMT-Extended/refs/heads/master/META-INF/com/google/android/update-binary" -o build/module-binary
        check "Module Binary"
    fi

    quotes "Getting Module Props"
    curl -LOSs "${BUILD_URL}module.prop" && curl -LOSs "${BUILD_URL}system.prop" && mv *.prop build/
    check "Module Props"

    if ! test -f "build/update-binary"; then
        quotes "Getting Kernel Zip Binary"
        curl -LOSs "${REPO_URL}toolchains/update-binary"
        check "Kernel Zip Binary"
    fi

    quotes "Getting Kernel Zip Script"
    curl -LOSs "${BUILD_URL}updater-script" && mv updater-script build/
    check "Kernel Zip Script"

    check "Build Environment"
}

toolchain ()
{
    separator
    if [[ "$USE_NEUTRON" == "true" ]]; then
        KERNELCLANG=NeutronClang-$NEUTRON
        CLANG_INFO="Neutron Clang ($NEUTRON)"
        TOOLCHAIN_PATH="toolchain/neutron-$NEUTRON"
    else
        if [[ "$LLVM" == "12" ]]; then
            CLANG=416183b1 # Clang 12.0.7
        elif [[ "$LLVM" == "13" ]]; then
            CLANG=433403b # Clang 13.0.3
        elif [[ "$LLVM" == "14" ]]; then
            CLANG=450784 # Clang 14.0.3
        elif [[ "$LLVM" == "15" ]]; then
            CLANG=468909b # Clang 15.0.3
        elif [[ "$LLVM" == "16" ]]; then
            CLANG=475365b # Clang 16.0.2
        elif [[ "$LLVM" == "17" ]]; then
            CLANG=498229b # Clang 17.0.4
        elif [[ "$LLVM" == "18" ]]; then
            CLANG=522817 # Clang 18.0.1
        elif [[ "$LLVM" == "19" ]]; then
            CLANG=536225 # Clang 19.0.1  
        elif [[ "$LLVM" == "20" ]]; then
            CLANG=547379 # Clang 20.0.0          
        else
            LLVM=21
            CLANG=563880 # Clang 21.0.0
        fi

        KERNELCLANG=Clang$LLVM
        CLANG_VERSION="r$CLANG"
        CLANG_INFO="Clang $LLVM (Based on $CLANG_VERSION)"
        TOOLCHAIN_PATH="toolchain/clang-$CLANG_VERSION"
    fi

    if test -d "$TOOLCHAIN_PATH"; then
        quotes "$CLANG_INFO Directory Found!"
    else
        if [[ "$USE_NEUTRON" == "true" ]]; then
            rm -rf $TOOLCHAIN_PATH
            mkdir -p $TOOLCHAIN_PATH
            quotes "Add $CLANG_INFO"
            separator
            cd $TOOLCHAIN_PATH
            bash <(curl -LSs "https://raw.githubusercontent.com/Neutron-Toolchains/antman/refs/heads/main/antman") -S=$NEUTRON
            if ! command -v file &> /dev/null; then
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
        else
            if [[ "$LLVM" == "12" ]]; then
                HOST=hub # GitHub
                ROM="ArrowOS-Devices" # ArrowOS
            elif [[ "$LLVM" -ge 13 && "$LLVM" -le 20 ]]; then
                HOST=lab
                ROM="crdroidandroid"
            else
                HOST=lab # GitLab
                ROM="reaPeR1010"
            fi

            TOOLCHAIN_URL="https://git$HOST.com/$ROM/android_prebuilts_clang_host_linux-x86_clang-$CLANG_VERSION.git"

            quotes "Add $CLANG_INFO as Submodule"
            git submodule add -f -q "$TOOLCHAIN_URL" "$TOOLCHAIN_PATH" > /dev/null
            check "clang-$CLANG_VERSION"
        fi
    fi

    ORIG_PATH=$PATH
    CLANG_DIR="$PWD/$TOOLCHAIN_PATH"
    PATH="$CLANG_DIR/bin:$ORIG_PATH"

    if [[ "$USE_NEUTRON" == "true" ]]; then
        ARGS="
            ARCH=arm64 O=out \
            LLVM=1 LLVM_IAS=1 \
        "
    else
        ARGS="
            ARCH=arm64 O=out \
            LLVM=1 LLVM_IAS=1 \
            CC=clang \
            READELF=$CLANG_DIR/bin/llvm-readelf \
        "
    fi
}

submodule_update ()
{
    separator
    quotes "Fetch all Submodules Update"

    git submodule update -f -q --init --recursive > /dev/null
    check "Submodules"
}

kernelsu ()
{
    separator

    if ! test -d "drivers/kernelsu"; then
        quotes "Add KernelSU Next as Submodule"
        separator

        if test -d "KernelSU-Next"; then
            rm -rf KernelSU-Next-gorhanhee
            rm -rf KernelSU-Next
            rm -rf Ke*
        fi

        git submodule add -f -q https://github.com/papaL3xa/KernelSU-Next-gorhanhee.git KernelSU-Next > /dev/null
        curl -LSs "https://raw.githubusercontent.com/papaL3xa/KernelSU-Next-gorhanhee/2e9038e96c0f7a05d0a36daf331b7cc6d1ab17e4/kernel/setup.sh" | bash -
        separator
        check "KernelSU Next"
    fi

    KSU_NEXT=ksu.config
}

kernel ()
{
    # Build Kernel Image
    separator
    noquotes "Fetch Kernel Info"
    separator
    noquotes "Device: $DEVICE ("$MODEL")"
    noquotes "SOC: Exynos 982$SOC"
    noquotes "Defconfig: $KERNEL_DEFCONFIG"
    noquotes "Kernel Version: $KERNEL_VERSION"
    noquotes "Build Date: `date +"%Y-%m-%d"`"

    if [[ "$KSU" == "y" ]]; then
        noquotes "KernelSU Next with SuSFS: Include"
    else
        noquotes "KernelSU Next with SuSFS: Not Include"
    fi

    noquotes "Toolchain: $CLANG_INFO"

    sed -i "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-$KERNEL_NAME-$KERNEL_VERSION-$DEVICE-$MODEL\"/" arch/arm64/configs/$KERNEL_DEFCONFIG
    sed -i "s/CONFIG_LOCALVERSION_AUTO=y/CONFIG_LOCALVERSION_AUTO=n/" arch/arm64/configs/$KERNEL_DEFCONFIG

    if [[ "$KSU" == "y" ]]; then
        DEFCONFIG="$KERNEL_DEFCONFIG bataxe.config $KSU_NEXT"
    else
        DEFCONFIG="$KERNEL_DEFCONFIG bataxe.config"
    fi

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

    rm -rf build/out/$MODEL
    mkdir -p build/out/$MODEL
}

dtb ()
{
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

ramdisk ()
{
    # Build Ramdisk
    separator
    quotes "Building Ramdisk"
    separator

    rm -rf build/AIK/s*
    mkdir -p build/AIK/split_img
    pushd build/AIK/split_img > /dev/null
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
    popd > /dev/null

    # Create Boot Image
    quotes "Calling Android Image Kitchen"
    pushd build/AIK > /dev/null

    mkdir -p ramdisk/debug_ramdisk
    mkdir -p ramdisk/dev
    mkdir -p ramdisk/mnt
    mkdir -p ramdisk/proc
    mkdir -p ramdisk/sys

    ./mkimg
    popd > /dev/null
}

build_zip ()
{
    # Build Zip
    separator
    quotes "Building Zip"
    if [[ "$LOCAL" == "y" ]] || [[ "$RELEASE" == "y" ]]; then
        separator
    fi

    pushd build > /dev/null
    rm -rf out/$MODEL/zip
    mkdir -p export
    mkdir -p out/$MODEL/zip/module/common/
    mkdir -p out/$MODEL/zip/module/META-INF/com/google/android
    mkdir -p out/$MODEL/zip/META-INF/com/google/android
    mv AIK/image-new.img out/$MODEL/boot-patched.img

    cp out/$MODEL/boot-patched.img out/$MODEL/zip/boot.img
    cp out/$MODEL/dtb_exynos982$SOC.img out/$MODEL/zip/dtb.img
    cp out/$MODEL/dtbo_$MODEL.img out/$MODEL/zip/dtbo.img
    cp update-binary out/$MODEL/zip/META-INF/com/google/android/
    mv updater-script out/$MODEL/zip/META-INF/com/google/android/

    mv module.prop out/$MODEL/zip/module/
    mv system.prop out/$MODEL/zip/module/common/
    cp module-binary out/$MODEL/zip/module/META-INF/com/google/android/update-binary
    echo -e "#MAGISK" > out/$MODEL/zip/module/META-INF/com/google/android/updater-script

    cd out/$MODEL/zip/module
    zip -r ../module.zip .
    rm -rf out/$MODEL/zip/module

    popd > /dev/null
    sed -i "s/ui_print(\" Kernel Version: \");/ui_print(\" Kernel Version: $KERNEL_VERSION\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    sed -i "s/ui_print(\" Kernel Device: \");/ui_print(\" Kernel Device: $DEVICE ($MODEL)\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script
    sed -i "s/ui_print(\" Kernel Toolchain: \");/ui_print(\" Kernel Toolchain: $CLANG_INFO\");/" build/out/$MODEL/zip/META-INF/com/google/android/updater-script

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

# Main Function
main ()
{
    START=`date +%s`

    separator
    quotes "Starting BatAxe Kernel Build Process"

    detect_env
    toolchain
    
    if [[ "$LOCAL" == "y" ]]; then
        submodule_update
    fi

    if [[ "$KSU" == "y" ]]; then
        kernelsu
    fi

    kernel
    dtb
    ramdisk
    build_zip

    if [[ "$LOCAL" == "y" ]]; then
        clean
        separator
    fi

    END=`date +%s`
    let "ELAPSED=$END-$START"

    quotes "Total Compile Time was $(($ELAPSED / 60)) Minutes and $(($ELAPSED % 60)) Seconds"
    separator
    
    # Output build result for GitHub Actions
    if [ ! -z "$GITHUB_ACTIONS" ]; then
        echo "BUILD_STATUS=success" >> $GITHUB_ENV
        FINAL_FILE=$(ls build/export/*.zip 2>/dev/null | head -1)
        if [ ! -z "$FINAL_FILE" ]; then
            echo "KERNEL_FILE=$(basename $FINAL_FILE)" >> $GITHUB_ENV
            echo "KERNEL_PATH=$FINAL_FILE" >> $GITHUB_ENV
        fi
    fi
}

# Run main function
main "$@"