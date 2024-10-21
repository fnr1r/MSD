# SPDX-FileCopyrightText: 2023-2024 Andrew Gunnerson
# SPDX-License-Identifier: GPL-3.0-only

source "${0%/*}/boot_common.sh" /data/local/tmp/msd/post-fs-data.log

# toybox's `mountpoint` command only works for directories, but bind mounts can
# be files too.
has_mountpoint() {
    local mnt=${1}

    awk -v "mnt=${mnt}" \
        'BEGIN { ret=1 } $5 == mnt { ret=0; exit } END { exit ret }' \
        /proc/self/mountinfo
}

header Patching SELinux policy

cp /sys/fs/selinux/policy "${log_dir}"/sepolicy.orig
"${mod_dir}"/msd-tool."$(getprop ro.product.cpu.abi)" sepatch -ST
cp /sys/fs/selinux/policy "${log_dir}"/sepolicy.patched

header Updating seapp_contexts

seapp_file=/system/etc/selinux/plat_seapp_contexts
seapp_temp_dir=${mod_dir}/seapp_temp
seapp_temp_file=${mod_dir}/seapp_temp/plat_seapp_contexts

mkdir -p "${seapp_temp_dir}"

nsenter --mount=/proc/1/ns/mnt -- \
    mount -t tmpfs "${app_id}" "${seapp_temp_dir}"

# Full path because Magisk runs this script in busybox's standalone ash mode and
# we need Android's toybox version of cp.
/system/bin/cp --preserve=a "${seapp_file}" "${seapp_temp_file}"

cat >> "${seapp_temp_file}" << EOF
user=_app isPrivApp=true name=${app_id} domain=msd_app type=app_data_file levelFrom=all
EOF

if [ "$KSU" == true ]; then
    # Mounting causes race conditions with other modules in KernelSU, so let's
    # just let OverlayFS handle it.
    OVLFS_TARGET="${mod_dir}${seapp_file}"
    mkdir -p "$(dirname "$OVLFS_TARGET")"
    /system/bin/cp "${seapp_temp_file}" "${OVLFS_TARGET}"

    # Copy timestamps from original file
    /system/bin/touch -r "${seapp_file}" "${OVLFS_TARGET}"
    # Except for ctime :(
    # Still works tho

    # Not removing that file is fine, since this script runs before overlay is
    # mounted, therefore we'll be patching the original file.
else
    while has_mountpoint "${seapp_file}"; do
        umount -l "${seapp_file}"
    done

    nsenter --mount=/proc/1/ns/mnt -- \
        mount -o ro,bind "${seapp_temp_file}" "${seapp_file}"
fi

# On some devices, the system time is set too late in the boot process. This,
# for some reason, causes the package manager service to not update the package
# info cache entry despite the mtime of the apk being newer than the mtime of
# the cache entry [1]. This causes the sysconfig file's hidden-api-whitelist
# option to not take effect, among other issues. Work around this by forcibly
# deleting the relevant cache entries on every boot.
#
# [1] https://cs.android.com/android/platform/superproject/+/android-13.0.0_r42:frameworks/base/services/core/java/com/android/server/pm/parsing/PackageCacher.java;l=139

header Clear package manager caches

ls -ldZ "${cli_apk%/*}"
find /data/system/package_cache -name "${app_id}-*" -exec ls -ldZ {} \+

run_cli_apk com.chiller3.msd.standalone.ClearPackageManagerCachesKt
