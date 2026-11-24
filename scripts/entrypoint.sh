#!/usr/bin/env bash
# Root-stage entrypoint: grant the runner user access to a mounted docker
# socket (whatever its host GID is), fix workdir ownership, then drop privileges.
set -euo pipefail

SOCK=/var/run/docker.sock
if [[ -S "$SOCK" ]]; then
  sock_gid=$(stat -c '%g' "$SOCK")
  if [[ "$sock_gid" == "0" ]]; then
    # Root-owned socket (e.g. Docker Desktop / podman): open it to the runner user.
    chmod 666 "$SOCK" 2>/dev/null || echo "[gh-runner] WARN: cannot grant runner access to docker.sock"
  else
    group=$(getent group "$sock_gid" | cut -d: -f1 || true)
    if [[ -z "$group" ]]; then
      group=dockerhost
      groupadd -g "$sock_gid" "$group"
    fi
    usermod -aG "$group" runner
  fi
fi

workdir="${RUNNER_WORKDIR:-/home/runner/_work}"
mkdir -p "$workdir"
chown runner:runner "$workdir"

# setpriv execs in place (no supervising parent to SIGKILL us during
# deregistration) and --init-groups picks up the docker group added above.
export HOME=/home/runner USER=runner
exec setpriv --reuid=runner --regid=runner --init-groups /usr/local/bin/start-runner.sh
