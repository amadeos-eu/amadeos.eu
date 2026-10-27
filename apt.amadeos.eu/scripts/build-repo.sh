#!/usr/bin/env bash
# Builds the signed apt repository of amadeOS from a pool of .deb files (collect.sh).
#
# Usage: build-repo.sh <pool-dir> <out-dir>
#
#   <out-dir>/pool/main/<repository>/*.deb          the packages, plus amadeos-archive-keyring
#   <out-dir>/dists/stable/main/binary-amd64/       Packages(.gz,.xz)
#   <out-dir>/dists/stable/main/dep11/              AppStream data (Components-amd64.yml.gz, icons-*.tar.gz)
#   <out-dir>/dists/stable/{Release,InRelease,Release.gpg}
#   <out-dir>/amadeos-archive-keyring.gpg (.asc)    the public key
#   <out-dir>/amadeos-archive-keyring.deb           the keyring package, for adding the repository by hand
#
# Environment: SIGNING_KEY (key ID or fingerprint of the signing subkey; empty = unsigned, for trying it out),
# SIGNING_PASSPHRASE (optional), SUITE (default stable).
#
# Needs apt-utils (apt-ftparchive), appstream + appstream-compose, imagemagick, gnupg, python3, dpkg-deb, xz.
set -euo pipefail

pool=$(realpath "${1:?usage: build-repo.sh <pool-dir> <out-dir>}")
out=${2:?usage: build-repo.sh <pool-dir> <out-dir>}
suite=${SUITE:-stable}
origin=amadeos
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

rm -rf "$out"
mkdir -p "$out/pool/main" "$out/dists/$suite/main/binary-amd64" "$out/dists/$suite/main/dep11"
out=$(realpath "$out")
cp -r "$pool/." "$out/pool/main/"

# --- amadeos-archive-keyring: the key and the source file, so that key changes reach systems as an update ---
key="$here/amadeos-archive-key.asc"
if [ -f "$key" ]; then
    gpg --dearmor < "$key" > "$out/amadeos-archive-keyring.gpg"
    cp "$key" "$out/amadeos-archive-keyring.asc"
    version=$(tr -d '[:space:]' < "$here/keyring-version")
    pkg="$work/keyring"
    mkdir -p "$pkg/DEBIAN" "$pkg/usr/share/keyrings" "$pkg/etc/apt/sources.list.d" "$pkg/usr/share/doc/amadeos-archive-keyring"
    cp "$out/amadeos-archive-keyring.gpg" "$pkg/usr/share/keyrings/"
    cat > "$pkg/etc/apt/sources.list.d/amadeos.sources" <<EOF
Types: deb
URIs: https://apt.amadeos.eu
Suites: $suite
Components: main
Signed-By: /usr/share/keyrings/amadeos-archive-keyring.gpg
EOF
    echo /etc/apt/sources.list.d/amadeos.sources > "$pkg/DEBIAN/conffiles"
    cat > "$pkg/DEBIAN/control" <<EOF
Package: amadeos-archive-keyring
Version: $version
Section: misc
Priority: optional
Architecture: all
Maintainer: amadeOS Project <developers@datazuul.com>
Description: Key and source of the amadeOS package repository
 The OpenPGP key that signs https://apt.amadeos.eu and the apt source
 that adds the repository, so that the amadeOS desktop, its applications
 and games are updated like the rest of the system.
EOF
    cat > "$pkg/usr/share/doc/amadeos-archive-keyring/copyright" <<EOF
The amadeOS archive key is public. Packaging: amadeOS Project, EUPL-1.2.
EOF
    mkdir -p "$out/pool/main/amadeos-archive-keyring"
    dpkg-deb --root-owner-group --build "$pkg" "$out/pool/main/amadeos-archive-keyring/amadeos-archive-keyring_${version}_all.deb" >/dev/null
    # Under a fixed name too, for installing it by hand on a system that does not know the repository yet.
    cp "$out/pool/main/amadeos-archive-keyring/amadeos-archive-keyring_${version}_all.deb" "$out/amadeos-archive-keyring.deb"
else
    echo "[build-repo] no amadeos-archive-key.asc yet, so no amadeos-archive-keyring package" >&2
fi

# --- Package index ---
cd "$out"
apt-ftparchive packages pool > "dists/$suite/main/binary-amd64/Packages"
gzip -9nk "dists/$suite/main/binary-amd64/Packages"
xz -9k "dists/$suite/main/binary-amd64/Packages"
cat > "dists/$suite/main/binary-amd64/Release" <<EOF
Archive: $suite
Origin: amadeOS
Label: amadeOS
Component: main
Architecture: amd64
EOF
echo "[build-repo] $(grep -c '^Package:' "dists/$suite/main/binary-amd64/Packages") packages"

# --- AppStream (DEP-11) from the metainfo files of the packages ---
catalogs=()
while IFS= read -r -d '' deb; do
    name=$(dpkg-deb -f "$deb" Package)
    root="$work/root/$name"
    rm -rf "$root"
    mkdir -p "$root"
    dpkg-deb -x "$deb" "$root"
    compgen -G "$root/usr/share/metainfo/*.xml" >/dev/null || continue
    # compose wants an icon of at least 64x64 px; the amade icons are 48x48 pixel art. For the catalog only (the
    # package stays as it is) larger sizes are added: 96x96 doubled without smoothing, and 128x128 from a 4x
    # enlargement scaled down, which compose turns into the 64x64 and 128x128 icons of the catalog.
    if ! compgen -G "$root/usr/share/icons/hicolor/*/apps/*" | grep -qvE '/(16x16|22x22|24x24|32x32|48x48)/'; then
        for icon in "$root"/usr/share/icons/hicolor/48x48/apps/*.png; do
            [ -f "$icon" ] || continue
            mkdir -p "$root/usr/share/icons/hicolor/96x96/apps" "$root/usr/share/icons/hicolor/128x128/apps"
            convert "$icon" -filter point -resize 200% "$root/usr/share/icons/hicolor/96x96/apps/$(basename "$icon")"
            convert "$icon" -filter point -resize 400% -filter box -resize 128x128 \
                "$root/usr/share/icons/hicolor/128x128/apps/$(basename "$icon")"
        done
    fi
    result="$work/compose/$name"
    if ! appstreamcli compose --no-net --origin="$origin" --prefix=/usr --result-root="$result" \
            --hints-dir="$work/hints/$name" "$root" > "$work/compose-$name.log" 2>&1; then
        echo "[build-repo] AppStream: $name has errors and is left out:" >&2
        sed 's/^/    /' "$work/compose-$name.log" >&2
        continue
    fi
    xml="$result/usr/share/swcatalog/xml/$origin.xml.gz"
    [ -f "$xml" ] && catalogs+=("$name=$xml")
done < <(find pool -name '*.deb' -print0 | sort -z)

dep11="dists/$suite/main/dep11"
python3 "$here/scripts/dep11.py" "$origin" "$work/Components.xml" "${catalogs[@]}"
appstreamcli convert --format=yaml "$work/Components.xml" "$work/Components-amd64.yml"
# apt only fetches an index whose uncompressed name the Release file lists, so the plain files stay next to the
# compressed ones (as in Debian's and Ubuntu's archives).
cp "$work/Components-amd64.yml" "$dep11/"
gzip -9nk "$dep11/Components-amd64.yml"
for size in 48x48 64x64 128x128; do
    mkdir -p "$work/icons/$size"
    for name in "$work"/compose/*; do
        [ -d "$name/usr/share/swcatalog/icons/$origin/$size" ] && cp "$name/usr/share/swcatalog/icons/$origin/$size/"* "$work/icons/$size/"
    done
    tar -C "$work/icons/$size" --sort=name --owner=0 --group=0 --numeric-owner -cf "$dep11/icons-$size.tar" .
    gzip -9nk "$dep11/icons-$size.tar"
done

# --- Release file and signatures ---
apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=amadeOS" \
    -o "APT::FTPArchive::Release::Label=amadeOS" \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o "APT::FTPArchive::Release::Architectures=amd64" \
    -o "APT::FTPArchive::Release::Components=main" \
    -o "APT::FTPArchive::Release::Description=amadeOS packages ($suite)" \
    release "dists/$suite" > "$work/Release"
mv "$work/Release" "dists/$suite/Release"

if [ -n "${SIGNING_KEY:-}" ]; then
    sign=(gpg --batch --yes --local-user "$SIGNING_KEY" --digest-algo SHA512)
    [ -n "${SIGNING_PASSPHRASE:-}" ] && sign+=(--pinentry-mode loopback --passphrase-fd 3)
    "${sign[@]}" --clearsign -o "dists/$suite/InRelease" "dists/$suite/Release" 3<<<"${SIGNING_PASSPHRASE:-}"
    "${sign[@]}" --armor --detach-sign -o "dists/$suite/Release.gpg" "dists/$suite/Release" 3<<<"${SIGNING_PASSPHRASE:-}"
    echo "[build-repo] signed with $SIGNING_KEY"
else
    echo "[build-repo] SIGNING_KEY not set: the repository is unsigned" >&2
fi

cp "$here/index.html" "$out/index.html"
