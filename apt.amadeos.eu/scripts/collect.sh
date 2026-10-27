#!/usr/bin/env bash
# Downloads the .deb files of the last stable releases of every amadeOS repository into a pool directory.
#
# Usage: collect.sh <pool-dir> <state-file>
#        LIST_ONLY=1 collect.sh <pool-dir> <state-file>     only write the state file, download nothing
#
# The repositories are those of repositories.list in datazuul/amadeos (main) plus extra-repositories.list next to
# this folder. Of each one, the KEEP (default 3) newest GitHub Releases that are neither drafts nor pre-releases
# are taken, with every *.deb asset. Files already in the pool are not downloaded again (when the pool is kept
# between runs), files of releases that dropped out are removed. The state file lists repository, tag, file and the
# SHA-256 digest GitHub reports (or the asset ID of an asset without one) of every package, sorted, so two runs with
# the same releases write the same file; the workflow compares it with the published one before downloading.
#
# Needs curl and jq; GITHUB_TOKEN (optional) raises the API rate limit.
set -euo pipefail

pool=${1:?usage: collect.sh <pool-dir> <state-file>}
state=${2:?usage: collect.sh <pool-dir> <state-file>}
keep=${KEEP:-3}
owner=${OWNER:-datazuul}
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
list_url=${REPOSITORIES_LIST_URL:-https://raw.githubusercontent.com/$owner/amadeos/main/repositories.list}

api() {
    curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/$1"
}

repos=$( { curl -fsSL --retry 3 "$list_url"; cat "$here/extra-repositories.list"; } \
    | sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' | sort -u)

mkdir -p "$pool"
tmp_state=$(mktemp)
wanted=$(mktemp)
trap 'rm -f "$tmp_state" "$wanted"' EXIT

for repo in $repos; do
    # Newest first; drafts are only visible with push rights anyway.
    releases=$(api "repos/$owner/$repo/releases?per_page=30" \
        | jq -c "[.[] | select(.draft | not) | select(.prerelease | not)] | .[:$keep][]")
    [ -n "$releases" ] || { echo "[collect] $repo: no stable release"; continue; }
    while IFS= read -r release; do
        tag=$(jq -r .tag_name <<<"$release")
        while IFS=$'\t' read -r name url digest id; do
            [ -n "$name" ] || continue
            printf '%s\t%s\t%s\t%s\n' "$repo" "$tag" "$name" "${digest:-asset-$id}" >> "$tmp_state"
            [ "${LIST_ONLY:-0}" = 1 ] && continue
            dir="$pool/$repo"
            mkdir -p "$dir"
            echo "$repo/$name" >> "$wanted"
            sha=${digest#sha256:}
            if [ ! -f "$dir/$name" ] || { [ -n "$sha" ] && ! sha256sum --status -c <<<"$sha  $dir/$name"; }; then
                echo "[collect] $repo $tag: $name"
                curl -fsSL --retry 3 -o "$dir/$name.part" "$url"
                mv "$dir/$name.part" "$dir/$name"
            fi
            # GitHub gives the digest of newer assets; check the download against it.
            if [ -n "$sha" ] && ! sha256sum --status -c <<<"$sha  $dir/$name"; then
                echo "[collect] $repo/$name does not match the digest GitHub reports" >&2
                exit 1
            fi
        done < <(jq -r '.assets[] | select(.name | endswith(".deb")) | [.name, .browser_download_url, (.digest // ""), .id] | @tsv' <<<"$release")
    done <<<"$releases"
done

sort "$tmp_state" > "$state"
if [ "${LIST_ONLY:-0}" = 1 ]; then
    echo "[collect] $(wc -l < "$state") packages listed"
    exit 0
fi

# Remove what is no longer wanted (older releases, repositories taken off the list).
while IFS= read -r -d '' file; do
    rel=${file#"$pool"/}
    grep -qxF "$rel" "$wanted" || { echo "[collect] dropping $rel"; rm -f "$file"; }
done < <(find "$pool" -type f -print0)
find "$pool" -mindepth 1 -type d -empty -delete

echo "[collect] $(wc -l < "$state") packages from $(cut -f1 "$state" | sort -u | wc -l) repositories"
