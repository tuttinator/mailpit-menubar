#!/bin/bash
# Build, notarize, and publish a Mailpit Menubar release to GitHub Releases.
#
#   Scripts/release.sh
#
# Pipeline: make bundle (Developer ID + hardened runtime) → notarize+staple app
# → DMG → notarize+staple DMG → generate_appcast → gh release create with the
# DMG, delta updates, and appcast.xml as assets.
#
# The app's SUFeedURL is .../releases/latest/download/appcast.xml, so every
# release must carry the full appcast; GitHub redirects "latest" to it.
#
# Requirements (one-time):
#   - Developer ID Application cert in Keychain (team 3W87X2JS5F)
#   - notarytool profile:
#       xcrun notarytool store-credentials mailpit-menubar-notary \
#         --apple-id ... --team-id 3W87X2JS5F --password <app-specific>
#   - Sparkle EdDSA key in login Keychain (generate_keys); the public half is
#     SUPublicEDKey in Resources/Info.plist
#   - gh CLI signed in with push access to the repo
#
# Environment overrides: NOTARY_PROFILE, SIGN_IDENTITY, GH_REPO.
# SPARKLE_ED_KEY_FILE (optional): path to an exported EdDSA private key
# (generate_keys -x). When unset, generate_appcast reads the Keychain, which
# may show a one-time "allow access" dialog.
#
# Version bumps: edit CFBundleShortVersionString + CFBundleVersion in
# Resources/Info.plist before running. Sparkle compares CFBundleVersion, so it
# must increase every release.
#
# Old DMGs are kept in releases/ (gitignored); generate_appcast uses them to
# build delta updates and a multi-version appcast. Don't delete them.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mailpit Menubar"
GH_REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mailpit-menubar-notary}"
TEAM_ID="3W87X2JS5F"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Caleb Tutty (${TEAM_ID})}"

WORK="${REPO}/build/release"
RELEASES="${REPO}/releases"
APP="${REPO}/build/${APP_NAME}.app"

# The baked-in feed must point at this repo's releases.
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${REPO}/Resources/Info.plist")"
EXPECTED_FEED="https://github.com/${GH_REPO}/releases/latest/download/appcast.xml"
if [ "${FEED_URL}" != "${EXPECTED_FEED}" ]; then
  echo "SUFeedURL in Resources/Info.plist (${FEED_URL}) does not match ${EXPECTED_FEED}" >&2
  exit 1
fi

if [ -n "$(git -C "${REPO}" status --porcelain)" ]; then
  echo "working tree is dirty — commit the version bump first" >&2
  exit 1
fi

rm -rf "${WORK}"
mkdir -p "${WORK}" "${RELEASES}"

echo "==> building signed bundle"
(cd "${REPO}" && make bundle SIGN_IDENTITY="${SIGN_IDENTITY}")

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
TAG="v${VERSION}"
DMG_NAME="Mailpit-Menubar-${VERSION}.dmg"
DOWNLOAD_BASE="https://github.com/${GH_REPO}/releases/download"
if [ -e "${RELEASES}/${DMG_NAME}" ] || gh release view "${TAG}" --repo "${GH_REPO}" >/dev/null 2>&1; then
  echo "release ${TAG} already exists — bump the version in Resources/Info.plist" >&2
  exit 1
fi

echo "==> notarizing app (v${VERSION}, build ${BUILD_NUM})"
ditto -c -k --keepParent "${APP}" "${WORK}/MailpitMenubar.zip"
xcrun notarytool submit "${WORK}/MailpitMenubar.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP}"

echo "==> building DMG"
DMG_ROOT="${WORK}/dmg-root"
mkdir -p "${DMG_ROOT}"
cp -R "${APP}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${WORK}/${DMG_NAME}"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${WORK}/${DMG_NAME}"

echo "==> notarizing DMG"
xcrun notarytool submit "${WORK}/${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${WORK}/${DMG_NAME}"
spctl --assess --type open --context context:primary-signature -v "${WORK}/${DMG_NAME}"

echo "==> generating appcast"
cp "${WORK}/${DMG_NAME}" "${RELEASES}/"
SPARKLE_BIN="${REPO}/.build/artifacts/sparkle/Sparkle/bin"
GEN_ARGS=(--download-url-prefix "${DOWNLOAD_BASE}/${TAG}/" --link "https://github.com/${GH_REPO}")
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  GEN_ARGS+=(--ed-key-file "${SPARKLE_ED_KEY_FILE}")
fi
"${SPARKLE_BIN}/generate_appcast" "${GEN_ARGS[@]}" "${RELEASES}"

# GitHub rewrites spaces in asset names, and each DMG lives under its own tag,
# so: rename "Mailpit Menubar<new>-<old>.delta" → "MailpitMenubar…", and point
# every full DMG at the tag it was released under. Enclosure URLs are not part
# of the signed payload, so this does not invalidate signatures.
for delta in "${RELEASES}/Mailpit Menubar"*.delta; do
  [ -e "${delta}" ] || continue
  mv "${delta}" "${RELEASES}/MailpitMenubar${delta##*/Mailpit Menubar}"
done
sed -E -i '' \
  -e 's#Mailpit(%20| )Menubar([0-9])#MailpitMenubar\2#g' \
  -e 's#releases/download/v[^/"]+/Mailpit-Menubar-([0-9][^/"]*)\.dmg#releases/download/v\1/Mailpit-Menubar-\1.dmg#g' \
  "${RELEASES}/appcast.xml"

echo "==> creating GitHub release ${TAG}"
ASSETS=("${RELEASES}/${DMG_NAME}" "${RELEASES}/appcast.xml")
for delta in "${RELEASES}/MailpitMenubar${BUILD_NUM}-"*.delta; do
  [ -e "${delta}" ] && ASSETS+=("${delta}")
done
git -C "${REPO}" tag -a "${TAG}" -m "Mailpit Menubar ${VERSION}"
git -C "${REPO}" push origin "${TAG}"
gh release create "${TAG}" --repo "${GH_REPO}" --title "Mailpit Menubar ${VERSION}" \
  --generate-notes --verify-tag "${ASSETS[@]}"

echo "==> done"
echo "    feed: ${EXPECTED_FEED}"
echo "    dmg:  ${DOWNLOAD_BASE}/${TAG}/${DMG_NAME}"
