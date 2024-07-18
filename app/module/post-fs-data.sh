# SPDX-FileCopyrightText: 2023-2024 Andrew Gunnerson
# SPDX-License-Identifier: GPL-3.0-only

source "${0%/*}/boot_common.sh" /data/local/tmp/msd.post-fs-data.log

header Patching SELinux policy

"${mod_dir}"/msd-tool."$(getprop ro.product.cpu.abi)" sepatch -ST

header Updating seapp_contexts

seapp_file=/system/etc/selinux/plat_seapp_contexts
seapp_temp_dir=${mod_dir}/seapp_temp
seapp_temp_file=${mod_dir}/seapp_temp/plat_seapp_contexts

mkdir -p "${seapp_temp_dir}"
mount -t tmpfs tmpfs "${seapp_temp_dir}"

# Full path because Magisk runs this script in busybox's standalone ash mode and
# we need Android's toybox version of cp.
/system/bin/cp --preserve=a "${seapp_file}" "${seapp_temp_file}"

cat >> "${seapp_temp_file}" << EOF
user=_app isPrivApp=true name=${app_id} domain=msd_app type=app_data_file levelFrom=all
EOF

mount -o ro,bind "${seapp_temp_file}" "${seapp_file}"

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
