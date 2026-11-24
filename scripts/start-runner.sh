#!/usr/bin/env bash
# Registers this container as a GitHub Actions runner, runs it, and
# deregisters on shutdown. All configuration comes from the environment.
set -euo pipefail
cd /home/runner

log() { echo "[gh-runner] $*"; }
die() { echo "[gh-runner] ERROR: $*" >&2; exit 1; }
truthy() { [[ "${1,,}" =~ ^(1|true|yes|on)$ ]]; }

: "${GITHUB_OWNER:?GITHUB_OWNER is required (org or user name)}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_URL="${GITHUB_URL:-https://github.com}"
GITHUB_URL="${GITHUB_URL%/}"
if [[ -z "${GITHUB_API_URL:-}" ]]; then
  if [[ "$GITHUB_URL" == "https://github.com" ]]; then
    GITHUB_API_URL="https://api.github.com"
  else
    GITHUB_API_URL="$GITHUB_URL/api/v3"   # GitHub Enterprise Server
  fi
fi
GITHUB_API_URL="${GITHUB_API_URL%/}"

if [[ -n "$GITHUB_REPO" ]]; then
  SCOPE=repo
  TARGET_URL="$GITHUB_URL/$GITHUB_OWNER/$GITHUB_REPO"
  API_PATH="repos/$GITHUB_OWNER/$GITHUB_REPO"
else
  SCOPE=org
  TARGET_URL="$GITHUB_URL/$GITHUB_OWNER"
  API_PATH="orgs/$GITHUB_OWNER"
fi

RUNNER_NAME="${RUNNER_NAME:-${RUNNER_NAME_PREFIX:-runner}-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/home/runner/_work}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_GROUP="${RUNNER_GROUP:-}"
EPHEMERAL="${EPHEMERAL:-false}"
DISABLE_AUTO_UPDATE="${DISABLE_AUTO_UPDATE:-false}"
NO_DEFAULT_LABELS="${NO_DEFAULT_LABELS:-false}"

# Fetch a registration or removal token from the API using the PAT.
api_token() {
  local kind=$1  # registration-token | remove-token
  [[ -n "${ACCESS_TOKEN:-}" ]] || return 1
  curl -fsSL -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$GITHUB_API_URL/$API_PATH/actions/runners/$kind" | jq -r .token
}

if [[ -n "${ACCESS_TOKEN:-}" ]]; then
  log "Requesting registration token for $SCOPE $GITHUB_OWNER${GITHUB_REPO:+/$GITHUB_REPO}"
  REG_TOKEN=$(api_token registration-token) || die "could not get a registration token (check ACCESS_TOKEN scopes)"
elif [[ -n "${RUNNER_TOKEN:-}" ]]; then
  REG_TOKEN="$RUNNER_TOKEN"
else
  die "set ACCESS_TOKEN (PAT, recommended) or RUNNER_TOKEN (one-time registration token)"
fi
[[ -n "$REG_TOKEN" && "$REG_TOKEN" != "null" ]] || die "empty registration token"

args=(--unattended --replace
      --url "$TARGET_URL"
      --token "$REG_TOKEN"
      --name "$RUNNER_NAME"
      --work "$RUNNER_WORKDIR")
[[ -n "$RUNNER_LABELS" ]] && args+=(--labels "$RUNNER_LABELS")
if [[ -n "$RUNNER_GROUP" ]]; then
  if [[ "$SCOPE" == org ]]; then
    args+=(--runnergroup "$RUNNER_GROUP")
  else
    log "RUNNER_GROUP ignored for repo-scoped runners"
  fi
fi
if truthy "$EPHEMERAL"; then args+=(--ephemeral); fi
if truthy "$DISABLE_AUTO_UPDATE"; then args+=(--disableupdate); fi
if truthy "$NO_DEFAULT_LABELS"; then args+=(--no-default-labels); fi

# A restarted non-ephemeral container still has the old registration on disk.
rm -f .runner .credentials .credentials_rsaparams

log "Configuring $RUNNER_NAME -> $TARGET_URL"
./config.sh "${args[@]}"

deregister() {
  log "Deregistering $RUNNER_NAME"
  local token
  token=$(api_token remove-token) || token="${RUNNER_TOKEN:-}"
  if [[ -n "$token" ]]; then
    ./config.sh remove --token "$token" || log "deregistration failed; remove it in the GitHub UI"
  else
    log "no token available to deregister; remove it in the GitHub UI"
  fi
}

on_signal() {
  log "Shutdown signal received"
  if [[ -n "${RUN_PID:-}" ]]; then
    kill -TERM "$RUN_PID" 2>/dev/null || true
    wait "$RUN_PID" 2>/dev/null || true
  fi
  deregister
  exit 0
}
trap on_signal SIGTERM SIGINT

# Job control on: without it, background children inherit SIGINT as ignored,
# and run.sh stops the listener by forwarding SIGINT, so it would never exit.
set -m
./run.sh &
RUN_PID=$!
set +e
wait "$RUN_PID"
rc=$?
set -e

# Ephemeral runners deregister themselves after their one job.
if ! truthy "$EPHEMERAL"; then deregister; fi
exit "$rc"
