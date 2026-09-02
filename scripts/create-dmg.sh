#!/bin/bash
# Packages the built app into a styled installer DMG.
# Runs as an Xcode post-action, so it reads TARGET_BUILD_DIR/WRAPPER_NAME from
# the build environment. The window geometry below matches the artwork drawn by
# scripts/make-dmg-background.swift; change both together.

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
app_path="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

# Xcode discards post-action output, so keep the last run's log next to the app.
exec > >(tee "${TARGET_BUILD_DIR}/create-dmg.log") 2>&1

window_width=640
window_height=400
icon_size=128
app_icon_x=170
alias_icon_x=470
icon_y=180

if [[ ! -d "${app_path}" ]]; then
    echo "error: App not found at ${app_path}"
    exit 1
fi

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "${app_path}/Contents/Info.plist" 2>/dev/null || true
}

volume_name="$(read_plist CFBundleDisplayName)"
volume_name="${volume_name:-${PRODUCT_NAME}}"
version="$(read_plist CFBundleShortVersionString)"
dmg_path="${TARGET_BUILD_DIR}/${volume_name}${version:+-${version}}.dmg"

work_directory="$(mktemp -d -t yazar-dmg)"
staging_directory="${work_directory}/root"
temporary_dmg="${work_directory}/writable.dmg"
mkdir "${staging_directory}"
mount_directory=""

cleanup() {
    if [[ -n "${mount_directory}" ]]; then
        hdiutil detach "${mount_directory}" -force -quiet || true
    fi

    rm -rf "${work_directory}"
}
trap cleanup EXIT

ditto "${app_path}" "${staging_directory}/${WRAPPER_NAME}"
ln -s /Applications "${staging_directory}/Applications"

# Finder needs one file holding both scale factors to pick the retina backdrop.
mkdir -p "${staging_directory}/.background"
tiffutil -cathidpicheck \
    "${script_directory}/dmg-background.png" \
    "${script_directory}/dmg-background@2x.png" \
    -out "${staging_directory}/.background/background.tiff" >/dev/null

# Finder writes .DS_Store into the mounted image, so leave room beyond the payload.
staged_kilobytes="$(du -sk "${staging_directory}" | cut -f1)"
hdiutil create \
    -volname "${volume_name}" \
    -srcfolder "${staging_directory}" \
    -fs HFS+ \
    -format UDRW \
    -size "$((staged_kilobytes + 20480))k" \
    -ov \
    -quiet \
    "${temporary_dmg}"

attach_output="$(hdiutil attach "${temporary_dmg}" -readwrite -noverify -noautoopen)"
mount_directory="$(printf '%s\n' "${attach_output}" | grep '/Volumes/' | head -1 | cut -f3-)"

if [[ -z "${mount_directory}" ]]; then
    echo "error: Could not mount ${temporary_dmg}"
    exit 1
fi

# A volume mounted under a name already in use gets a suffix, so style the disk
# under the name it actually mounted with.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$(basename "${mount_directory}")"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 140, $((200 + window_width)), $((140 + window_height))}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${icon_size}
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set shows item info of viewOptions to false
        set shows icon preview of viewOptions to true
        set background picture of viewOptions to file ".background:background.tiff"
        set extension hidden of file "${WRAPPER_NAME}" to true
        set position of item "${WRAPPER_NAME}" to {${app_icon_x}, ${icon_y}}
        set position of item "Applications" to {${alias_icon_x}, ${icon_y}}
        update without registering applications
        close
        delay 1
        open
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Reuse the app icon as the volume icon. Finder deletes this file if it is
# already there while the window is being styled, so add it afterwards.
icon_name="$(read_plist CFBundleIconFile)"
icon_path="${app_path}/Contents/Resources/${icon_name%.icns}.icns"
if [[ -f "${icon_path}" ]] && command -v SetFile >/dev/null; then
    cp "${icon_path}" "${mount_directory}/.VolumeIcon.icns"
    SetFile -a C "${mount_directory}" || true
fi

# Give Finder time to flush .DS_Store before the image is unmounted.
sync

for attempt in 1 2 3 4 5; do
    if hdiutil detach "${mount_directory}" -quiet; then
        mount_directory=""
        break
    fi

    if [[ "${attempt}" == 5 ]]; then
        echo "error: Could not unmount ${mount_directory}"
        exit 1
    fi

    /bin/sleep 2
done

hdiutil convert \
    "${temporary_dmg}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -quiet \
    -o "${dmg_path}"

echo "Created ${dmg_path}"
