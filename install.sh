#!/usr/bin/env bash
# Installs the pdeploy launcher into ~/.local/bin and both Dockerfiles into
# ~/.local/share/pdeploy. Auto-builds the standard image; the zksync image is
# opt-in via `pdeploy build --zksync`.
#
# Works two ways:
#   ./install.sh                                                        (local checkout)
#   curl -fsSL https://raw.githubusercontent.com/brickpop/pdeploy/main/install.sh | bash
#
# Detection is by observed files, not by BASH_SOURCE tricks: if the three
# sibling files exist next to this script, we copy from there; otherwise we
# fetch them from RAW_BASE.
set -euo pipefail

RAW_BASE="${PDEPLOY_RAW_BASE:-https://raw.githubusercontent.com/brickpop/pdeploy/main}"
FILES=(pdeploy Dockerfile Dockerfile.zksync)

bin="${HOME}/.local/bin"
share="${PDEPLOY_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pdeploy}"

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
mode="remote"
if [ -n "$src_dir" ]; then
  mode="local"
  for f in "${FILES[@]}"; do
    [ -f "$src_dir/$f" ] || { mode="remote"; break; }
  done
fi

command -v podman >/dev/null || { echo "podman is not installed — see the README" >&2; exit 1; }
[ "$mode" = "local" ] || command -v curl >/dev/null || { echo "curl is required for remote install" >&2; exit 1; }

mkdir -p "$bin" "$share"

fetch() {  # $1 = repo-relative path, $2 = destination, $3 = mode
  local from="$1" to="$2" perms="$3"
  if [ "$mode" = "local" ]; then
    install -m "$perms" "$src_dir/$from" "$to"
    echo "installed (local):  $to"
  else
    curl -fsSL "$RAW_BASE/$from" -o "$to"
    chmod "$perms" "$to"
    echo "installed (remote): $to"
  fi
}

fetch pdeploy           "$bin/pdeploy"            0755
fetch Dockerfile        "$share/Dockerfile"       0644
fetch Dockerfile.zksync "$share/Dockerfile.zksync" 0644

"$bin/pdeploy" build "$@"

case ":$PATH:" in
  *":$bin:"*) ;;
  *)
    echo
    echo "NOTE: $bin is not on your PATH. Add it:"
    echo "  bash/zsh:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "  fish:      fish_add_path ~/.local/bin"
    ;;
esac

echo
echo "Done. Standard image built."
echo "To build the zksync image:  pdeploy build --zksync"
