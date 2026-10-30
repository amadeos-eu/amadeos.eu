# apt.amadeos.eu

The signed apt repository of amadeOS (ROADMAP M16): the `.deb` packages of the desktop, the applications and the
games, so that an installed amadeOS gets their updates like Debian's, in the Front Panel and in Software.

```
apt.amadeos.eu/
  scripts/collect.sh        downloads the .deb assets of the last 3 stable GitHub Releases of every repository
  scripts/build-repo.sh     Packages, AppStream data (DEP-11), Release, signatures, amadeos-archive-keyring
  scripts/dep11.py          merges the AppStream catalogs of the packages and adds the package names
  extra-repositories.list   repositories besides repositories.list of amadeos-eu/amadeos
  amadeos-archive-key.asc   the public key (the primary key stays offline with Ralf)
  keyring-version           version of the amadeos-archive-keyring package; raise it when the key or the source change
  index.html                the page at https://apt.amadeos.eu/
```

## How a release gets to the systems

1. A repository is promoted to `main`; its build tags `vX.Y.Z` and attaches the `.deb` files to a GitHub Release
   (amadeos-eu/amadeos-ci `release`).
2. The workflow [`apt-repository.yml`](../.github/workflows/apt-repository.yml) runs every 30 minutes. It lists the
   stable releases of all repositories (only API calls) and compares the list with `https://apt.amadeos.eu/state.txt`.
   Nothing new: it stops. Otherwise it downloads the packages, builds and signs the repository and uploads it with
   rsync. A push to `apt.amadeos.eu/` and *Run workflow* (with *force*) start it too.
3. apt on the systems fetches the new index with its daily refresh (`apt-daily.timer`), and the Front Panel shows
   the update.

The repository has one suite, `stable`, with the component `main` for `amd64`; all packages are `Architecture: all`.
Builds of the `release` and `develop` branches (testing, dev) are not in it yet: they are only workflow
artifacts so far, not releases.

### Layout on the server

```
/var/www/apt.amadeos.eu/
  pool/main/<repository>/<package>_<version>_all.deb
  dists/stable/InRelease, Release, Release.gpg
  dists/stable/main/binary-amd64/Packages(.gz, .xz)
  dists/stable/main/dep11/Components-amd64.yml(.gz), icons-{48x48,64x64,128x128}.tar(.gz)
  amadeos-archive-keyring.deb, .gpg, .asc       key package and key under fixed names
  state.txt                                     what was published (compared by the next run)
```

The AppStream data is made with `appstreamcli compose` from the metainfo files of the packages. compose wants an
icon of at least 64×64 pixels and the amade icons are 48×48, so for the catalog (not in the package) the script
adds a 96×96 copy doubled without smoothing and a 128×128 one; packages that ship larger icons use theirs.

## Setting it up (once)

1. **Key** (on Ralf's computer; the primary key never leaves it):
   ```sh
   gpg --quick-generate-key "amadeOS Archive Signing Key <developers@datazuul.com>" ed25519 cert 10y
   FPR=$(gpg --with-colons -k "amadeOS Archive" | awk -F: '/^fpr/{print $10; exit}')
   gpg --quick-add-key $FPR ed25519 sign 2y
   SUB=$(gpg --with-colons -k $FPR | awk -F: '/^fpr/{n++; if(n==2) print $10}')
   gpg --armor --export $FPR > amadeos-archive-key.asc                       # public: into this folder
   gpg --armor --export-secret-subkeys "$SUB!" > apt-signing-subkey.asc      # secret APT_SIGNING_KEY
   gpg --armor --export-secret-keys $FPR > amadeos-archive-primary-BACKUP.asc # offline backup, with
   ls ~/.gnupg/openpgp-revocs.d/                                             # the revocation certificate
   ```
2. **Server**: DNS A record `apt.amadeos.eu` (no AAAA), an SSH key for the upload
   (`ssh-keygen -t ed25519 -N '' -C amadeos-apt-deploy -f ~/.ssh/amadeos-apt-deploy`), then
   `ansible-playbook -i inventories/production playbooks/deploy-apt.amadeos.eu.yml` in datazuul-devops. It sets up
   nginx with TLS and the user `amadeos-apt`, whose key may only rsync into the web root.
3. **Secrets** of this repository (Settings → Secrets and variables → Actions):

   | Secret | Content |
   |---|---|
   | `APT_SIGNING_KEY` | `apt-signing-subkey.asc` |
   | `APT_SIGNING_PASSPHRASE` | the passphrase of the key |
   | `APT_DEPLOY_SSH_KEY` | `~/.ssh/amadeos-apt-deploy` (the private key) |
   | `APT_DEPLOY_KNOWN_HOSTS` | output of `ssh-keyscan -t ed25519 <server>` |
   | `APT_DEPLOY_HOST` | the server's host name or IP address |

   Until the secrets exist the workflow only prints a notice.
4. *Actions → apt repository → Run workflow*, then check `https://apt.amadeos.eu/dists/stable/InRelease`.

## On a system

amadeOS images newer than 1.0.0 install `amadeos-archive-keyring`, which brings the key
(`/usr/share/keyrings/amadeos-archive-keyring.gpg`) and the source (`/etc/apt/sources.list.d/amadeos.sources`).
An amadeOS installed from 1.0.0 gets it once by hand:

```sh
curl -fsSLO https://apt.amadeos.eu/amadeos-archive-keyring.deb
sudo apt install ./amadeos-archive-keyring.deb && sudo apt update
```

## Key changes

The signing subkey expires after two years. Before that, on Ralf's computer: `gpg --quick-set-expire $FPR 2y $SUB`
(or a new subkey with `--quick-add-key`, then a new `APT_SIGNING_KEY`), export the public key again into
`amadeos-archive-key.asc` and raise `keyring-version`. The next run publishes the new `amadeos-archive-keyring`,
and the systems take the new key with their next update, while the old one is still valid. If the subkey is
stolen: revoke it (`gpg --edit-key $FPR`, `key 1`, `revkey`), add a new one and do the same.

## Notes

- GitHub stops scheduled workflows of a repository without activity for 60 days and says so by mail; *Enable
  workflow* on the Actions page starts it again.
- Old versions stay in the pool for the last three releases of each repository, so a broken update can be undone
  with `sudo apt install <package>=<version>`.
