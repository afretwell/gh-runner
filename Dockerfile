# Self-hosted GitHub Actions runner, configured entirely from environment variables.
ARG RUNNER_VERSION=2.338.2
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

# Space-separated apt packages to bake into the image (e.g. "make python3-pip").
ARG EXTRA_PACKAGES=""

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl jq ca-certificates ${EXTRA_PACKAGES} \
 && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 scripts/start-runner.sh /usr/local/bin/start-runner.sh

# The entrypoint starts as root only to grant docker.sock access,
# then drops to the unprivileged `runner` user.
WORKDIR /home/runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
