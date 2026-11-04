#!/usr/bin/env python3
"""Patch the official KernelSU Next v3.0.1 manager for the legacy 4.14 KSU ABI.

Build target: legacy KSU_VERSION 32473 / Android 12 / Linux 4.14.
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

    // v3.0.1 already ships this legacy prctl reader in ksu.h.
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

    // This legacy 4.14 kernel uses the LSM hook integration.
    const auto legacy = legacy_get_info();
    return legacy.first > 0 ? "LSM (legacy)" : "Unavailable";
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

    // The legacy ABI has no version-tag ioctl.
    const auto legacy = legacy_get_info();
    return legacy.first > 0 ? "Legacy API" : "Unavailable";
}"""

for old, new, label in (
    (old_version, new_version, "get_version"),
    (old_hook, new_hook, "get_hook_mode"),
    (old_tag, new_tag, "get_version_tag"),
):
    if old not in src:
        raise SystemExit(f"Expected v3.0.1 {label} implementation not found; refusing patch")
    src = src.replace(old, new, 1)

path.write_text(src)
print("Patched v3.0.1 legacy version, hook mode and version tag.")
