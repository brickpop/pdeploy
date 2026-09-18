# pdeploy

Run a deployment ceremony inside a Podman container, sandboxed to the directory
you launch it from. Two prebuilt images — one for standard EVM and one for
zkSync — with `just`, git, Foundry (or `foundry-zksync`) and the rest of the
tooling the checklist calls for already baked in. No `apt install`, no
`foundryup`, no state left behind between sessions.

```sh
cd ~/dev/aragon/protocol-factory
pdeploy                 # interactive shell in the standard EVM image
pdeploy --zksync        # interactive shell in the zkSync image
```

## Install

**1. Install Podman**

```sh
sudo dnf install podman          # Fedora / RHEL / CentOS
sudo apt install podman          # Debian / Ubuntu
sudo pacman -S podman            # Arch
brew install podman && podman machine init && podman machine start   # macOS
```

On macOS you only need `podman machine init` once. If the VM happens to be
stopped when you run `pdeploy`, the launcher will `podman machine start` it for
you and continue. If no machine exists at all it refuses — creating one is a
resource decision (RAM/disk allocation) that shouldn't happen silently.

**2. Install pdeploy**

One-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/brickpop/pdeploy/main/install.sh | bash
```

Or from a checkout:

```sh
git clone https://github.com/brickpop/pdeploy.git
cd pdeploy
./install.sh
```

Either path copies the launcher to `~/.local/bin/pdeploy`, both Dockerfiles to
`~/.local/share/pdeploy`, and builds the **standard** image. The zkSync image is
opt-in — it takes another few minutes and you may not need it:

```sh
pdeploy build --zksync
```

If `~/.local/bin` is not on your `PATH`:

```sh
fish_add_path ~/.local/bin                                    # fish
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc      # bash/zsh
```

## Usage

```sh
pdeploy                        # shell in localhost/pdeploy
pdeploy --zksync               # shell in localhost/pdeploy-zksync
pdeploy just test              # run `just test` in the standard image
pdeploy --zksync just deploy   # run `just deploy` in the zksync image
```

Reserved subcommands are namespaced by name, not by flag:

| Subcommand | |
|---|---|
| *(none)* | Interactive bash shell in the current directory |
| `build` | Build the image |
| `update` | Rebuild it from scratch, pulling the latest base |
| `help` | Usage |

`--zksync` selects the zkSync variant for any of the above. Everything else on
the command line is passed straight through: to `podman build` for `build` and
`update`, or to the container as the command to run otherwise.

### Deployment ceremony

`pdeploy` replaces the "get a debian container running, then apt-install
everything, then foundryup" prelude in the manual checklist. From the moment
you're at the shell prompt, the ceremony is unchanged:

```sh
cd ~/dev/aragon/protocol-factory
pdeploy
# now inside the container, at the same path:
just init sepolia
just env         # verify parameters
just test
just predeploy   # simulate
just balance
just deploy
```

## What gets mounted

| Host | Container | |
|---|---|---|
| `$PWD` | `$PWD` (same path) | read-write — the only project code the container can see |
| `~/.gitconfig` | `/home/deployer/.gitconfig` | read-only, if present |

Running in `$HOME` itself is refused — set `PDEPLOY_ALLOW_HOME=1` to override.

The project keeps its host path inside the container, so tools that key state
off the working directory (Foundry cache, `just` recipes) behave the same way
inside and out.

## Env-var injection

Deployments need `DEPLOYER_KEY`, `ETHERSCAN_API_KEY` and friends in the
container. `pdeploy` picks one of two strategies at run time:

1. **If `vars` is on your host PATH:**
   ```
   vars resolve --partial --dotenv
   ```
   is invoked and its output passed to Podman as `--env-file`. This matches the
   manual `--env-file <(vars resolve --partial --dotenv 2>/dev/null)` step in
   the checklist. If `PDEPLOY_VARS_PROFILE` is set, `--profile $PDEPLOY_VARS_PROFILE`
   is appended so per-profile secrets (e.g. a `sepolia`-specific `DEPLOYER_KEY`)
   are picked up.

   When `PDEPLOY_VARS_PROFILE` is *not* set, pdeploy will auto-fill it from
   `lib/just-foundry/.env`. Projects without that layout are unaffected.
2. **Otherwise:** these variables are forwarded from your shell, if set:
   `DEPLOYER_KEY`, `ETHERSCAN_API_KEY`, `TERM`, `COLORTERM`.

Project-scoped variables (`MANAGEMENT_DAO_*`, plugin metadata URIs, …) live in
the repo's own `.env` and are read by `just` inside the container — nothing to
do on the host.

For anything else, use `PDEPLOY_ARGS`:

```sh
PDEPLOY_ARGS="-e MANAGEMENT_DAO_METADATA_URI=ipfs://... -v $HOME/keys:/keys:z" pdeploy
```

## What's in the images

Both images are based on `debian:trixie-slim` and add the checklist's tools:
`just git vim bc jq curl ca-certificates`, plus:

| Image | Foundry |
|---|---|
| `localhost/pdeploy` | standard Foundry — `forge`, `cast`, `anvil`, `chisel` |
| `localhost/pdeploy-zksync` | standard Foundry **plus** `foundry-zksync` — `forge-zksync`, `cast-zksync`, `anvil-zksync` alongside the standard binaries |

Pin a specific version at build time:

```sh
pdeploy build          --build-arg FOUNDRY_VERSION=1.7.1
pdeploy build --zksync --build-arg FOUNDRY_ZKSYNC_VERSION=v0.0.12
```

Refresh the base image and the toolchain:

```sh
pdeploy update
pdeploy update --zksync
```

## SELinux

On Fedora/RHEL, bind mounts are relabelled with `:z` (shared label, safe for
concurrent sessions). The stricter `:Z` gives each container a private MCS
category, which means a second `pdeploy` would relabel the mount out from under
the first — use `PDEPLOY_RELABEL=Z` only if you run one session at a time. On
non-SELinux hosts no suffix is added.

To undo the relabelling of a directory later: `restorecon -R <dir>`.

## Configuration

| Variable | Default | |
|---|---|---|
| `PDEPLOY_IMAGE` | `localhost/pdeploy` | standard image name |
| `PDEPLOY_IMAGE_ZKSYNC` | `localhost/pdeploy-zksync` | zkSync image name |
| `PDEPLOY_HOME` | `~/.local/share/pdeploy` | where the Dockerfiles live |
| `PDEPLOY_ARGS` | — | extra `podman run` args |
| `PDEPLOY_RELABEL` | `auto` | `z`, `Z` or `off` |
| `PDEPLOY_ALLOW_HOME` | — | `1` allows running in `$HOME` |
| `PDEPLOY_VARS_PROFILE` | — | profile forwarded to `vars resolve` as `--profile <value>` |
| `PDEPLOY_RAW_BASE` | `https://raw.githubusercontent.com/brickpop/pdeploy/main` | where `install.sh` fetches files from when run via `curl \| bash` |

## Uninstall

```sh
rm ~/.local/bin/pdeploy
rm -rf ~/.local/share/pdeploy
podman rmi -f $(podman images 'localhost/pdeploy*' -q)
```
