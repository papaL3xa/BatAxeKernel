#!/usr/bin/env bash
set -euo pipefail

VARIANT="${1:?Usage: $0 rksu|ksun|official-susfs [ref]}"
REF_OVERRIDE="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

mkdir -p ksu-src

case "$VARIANT" in
  rksu)
    REPO="https://github.com/rsuntk/KernelSU.git"
    REF="${REF_OVERRIDE:-master}"
    SRC="ksu-src/rksu"
    CONFIG="ci/ksu-configs/ksu-rksu.config"
    SUSFS="no"
    ;;
  ksun)
    REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
    REF="${REF_OVERRIDE:-legacy}"
    SRC="ksu-src/ksun"
    CONFIG="ci/ksu-configs/ksu-ksun.config"
    SUSFS="no"
    ;;
  official-susfs)
    REPO="https://github.com/tiann/KernelSU.git"
    REF="${REF_OVERRIDE:-v0.9.5}"
    SRC="ksu-src/official"
    CONFIG="ci/ksu-configs/ksu-official-susfs.config"
    SUSFS="yes"
    ;;
  *)
    echo "Unknown variant: $VARIANT" >&2
    exit 2
    ;;
esac

if [[ -e "$SRC" ]]; then
  rm -rf "$SRC"
fi

# Fetch a branch, tag, or exact commit SHA. The resolved commit is recorded below.
mkdir -p "$SRC"
git -C "$SRC" init -q
git -C "$SRC" remote add origin "$REPO"
git -C "$SRC" fetch --depth=1 --tags origin "$REF"
git -C "$SRC" checkout --detach -q FETCH_HEAD
KSU_SHA="$(git -C "$SRC" rev-parse HEAD)"

if [[ ! -f "$SRC/kernel/Kconfig" || ! -f "$SRC/kernel/Makefile" ]]; then
  echo "Kernel integration files not found in $SRC/kernel" >&2
  exit 3
fi

# BatAxeKernel rsuntk already contains these Kbuild/Kconfig hooks.
# Refuse to patch unknown trees or create a dangling driver link.
grep -q 'obj-$(CONFIG_KSU).*kernelsu/' drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig

if [[ -e drivers/kernelsu && ! -L drivers/kernelsu ]]; then
  echo "drivers/kernelsu exists and is not a symlink; refusing to overwrite it" >&2
  exit 4
fi
rm -f drivers/kernelsu
ln -s "../${SRC}/kernel" drivers/kernelsu

cp "$CONFIG" arch/arm64/configs/ksu.config

if [[ "$SUSFS" == "yes" ]]; then
  PATCH_DIR="patches/susfs-1.5.12"
  KERNEL_PATCH="$PATCH_DIR/exynos9825-4.14.113-kernel.patch"
  KSU_PATCH="$PATCH_DIR/official-ksu-v0.9.5.patch"

  # Do not silently use a generic 4.14 patch on Samsung Exynos.
  # These two patches must be specifically reviewed/ported for this source tree.
  for patch in "$KERNEL_PATCH" "$KSU_PATCH"; do
    if [[ ! -s "$patch" ]]; then
      echo "Missing reviewed SUSFS patch: $patch" >&2
      echo "C variant is intentionally blocked until Exynos 9825 / 4.14.113 patches are supplied." >&2
      exit 5
    fi
  done

  git apply --check "$KERNEL_PATCH"
  git apply "$KERNEL_PATCH"
  git -C "$SRC" apply --check "$ROOT/$KSU_PATCH"
  git -C "$SRC" apply "$ROOT/$KSU_PATCH"
fi

mkdir -p build
{
  echo "variant=$VARIANT"
  echo "repo=$REPO"
  echo "ref=$REF"
  echo "commit=$KSU_SHA"
  echo "susfs=$SUSFS"
} | tee build/ksu-source-info.txt

echo "Prepared $VARIANT from $KSU_SHA"
