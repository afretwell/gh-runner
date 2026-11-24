# gh-runner

Run a self-hosted GitHub Actions runner in Docker. You configure it with a `.env` file.

It builds on the official [`ghcr.io/actions/actions-runner`](https://github.com/actions/runner/pkgs/container/actions-runner) image. On start it registers with your repo or org, and on stop it deregisters.

## Quick start

```bash
git clone https://github.com/afretwell/gh-runner.git
cd gh-runner
cp .env.example .env      # set GITHUB_OWNER, GITHUB_REPO and ACCESS_TOKEN
docker compose up -d --build
docker compose logs -f
```

The runner then shows up under **Settings → Actions → Runners**. To use it from a workflow:

```yaml
jobs:
  build:
    runs-on: [self-hosted, docker]
```

To stop and deregister it:

```bash
docker compose down
```

## Configuration

Every setting lives in `.env`. See [`.env.example`](.env.example) for the full list.

| Variable | Default | Description |
|---|---|---|
| `GITHUB_OWNER` | **required** | The org or user that owns the runner |
| `GITHUB_REPO` | *(empty)* | Repo name. Leave it empty to register an org-wide runner |
| `ACCESS_TOKEN` | | PAT used to fetch registration and removal tokens (recommended) |
| `RUNNER_TOKEN` | | One-time registration token from the UI. Used only if `ACCESS_TOKEN` is unset |
| `RUNNER_NAME_PREFIX` | `runner` | The runner is named `<prefix>-<container hostname>` |
| `RUNNER_NAME` | | Exact runner name. Use it only with a single replica |
| `RUNNER_LABELS` | | Comma-separated extra labels |
| `RUNNER_GROUP` | | Runner group (org runners only; the group must already exist) |
| `RUNNER_WORKDIR` | `/home/runner/_work` | Job working directory |
| `EPHEMERAL` | `false` | Take one job and then re-register a fresh runner |
| `DISABLE_AUTO_UPDATE` | `false` | Pass `--disableupdate` |
| `NO_DEFAULT_LABELS` | `false` | Drop the `self-hosted`/OS/arch labels |
| `RUNNER_REPLICAS` | `1` | Number of identical runner containers |
| `RUNNER_VERSION` | `2.338.2` | Tag of the runner image to build from |
| `EXTRA_PACKAGES` | | apt packages to bake into the image |
| `DOCKER_SOCK` | `/var/run/docker.sock` | Host Docker socket mounted for jobs |
| `GITHUB_URL` | `https://github.com` | Set this for GitHub Enterprise Server |
| `GITHUB_API_URL` | *(derived)* | Overrides the API base URL |

### Token permissions

| Scope | Classic PAT | Fine-grained PAT |
|---|---|---|
| Repo runner | `repo` | Repository → Administration: read/write |
| Org runner | `admin:org` | Organization → Self-hosted runners: read/write |

With a PAT, the runner gets a new registration token every time it starts, so restarts and ephemeral cycling keep working. A UI `RUNNER_TOKEN` expires after one hour and cannot re-register the runner after a restart.

## Notes

- **Ephemeral mode** (`EPHEMERAL=true`): each container runs one job, deregisters, and exits. `restart: unless-stopped` then brings up a clean runner. Use this for untrusted or public-repo workloads.
- **Scaling:** use `RUNNER_REPLICAS=4 docker compose up -d`, or `docker compose up -d --scale runner=4`.
- **Docker access:** the host socket is mounted so jobs can run `docker`. The entrypoint matches the socket's GID so the unprivileged `runner` user can use it. Remove the volume if jobs must not reach the host daemon, because socket access is effectively root on the host.
- **Public repos:** GitHub advises against self-hosted runners on public repos, since forks can run code on your machine. If you do it anyway, use ephemeral mode and require approval for fork PR workflows.

## License

MIT
