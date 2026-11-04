#!/usr/bin/env python3
"""Compatibility patch for KernelSU Next Manager on legacy KSU 4.14 drivers.

The old BatAxe/rsuntk driver exposes version/flags through the legacy prctl
interface, but does not implement GET_HOOK_MODE or GET_VERSION_TAG ioctls.
"""
from pathlib import Path

path = Path("app/src/main/cpp/ksu.cc")
src = path.read_text()

old_version = """uint32_t get_version() {
    auto info = get_info();
    return info.version;
}"""
new_version = """uint32_t get_version() {
    auto info = get_info();
    if (info.version > 0) {
        return info.version;
    }

    // Legacy 4.14 KSU drivers report their real numeric version via prctl.
    const auto legacy = legacy_get_info();
    return legacy.first > 0 ? static_cast<uint32_t>(legacy.first) : 0;
}"""

old_hook = """const char* get_hook_mode(void)
{
    static struct ksu_get_hook_mode_cmd cmd = {0};

    if (ksuctl(KSU_IOCTL_GET_HOOK_MODE, &cmd) == 0)
        return cmd.mode;

    return "Unknown";
}"""
new_hook = """const char* get_hook_mode(void)
{
    static struct ksu_get_hook_mode_cmd cmd = {0};

    if (ksuctl(KSU_IOCTL_GET_HOOK_MODE, &cmd) == 0 && cmd.mode[0] != '\\0')
        return cmd.mode;

    // The legacy driver has no GET_HOOK_MODE ioctl. Its Note10 integration
    // uses LSM security hooks (ksu_lsm_hook_init), so label this as a source-verified fallback.
    const auto legacy = legacy_get_info();
    return legacy.first > 0 ? "LSM*" : "Unknown";
}"""

old_tag = """const char* get_version_tag(void)
{
    static struct ksu_get_version_tag_cmd cmd = {0};

    if (ksuctl(KSU_IOCTL_GET_VERSION_TAG, &cmd) == 0)
        return cmd.tag;

    return "Unknown";
}"""
new_tag = """const char* get_version_tag(void)
{
    static struct ksu_get_version_tag_cmd cmd = {0};

    if (ksuctl(KSU_IOCTL_GET_VERSION_TAG, &cmd) == 0 && cmd.tag[0] != '\\0')
        return cmd.tag;

    // This driver predates the version-tag ioctl; do not invent a tag.
    const auto legacy = legacy_get_info();
    return legacy.first > 0 ? "Legacy API" : "Unknown";
}"""

for old, new, label in (
    (old_version, new_version, "get_version"),
    (old_hook, new_hook, "get_hook_mode"),
    (old_tag, new_tag, "get_version_tag"),
):
    if old not in src:
        raise SystemExit(f"Expected upstream {label} implementation not found; refusing an unsafe patch")
    src = src.replace(old, new, 1)

path.write_text(src)
print("Patched legacy version, hook-mode and version-tag fallbacks.")
