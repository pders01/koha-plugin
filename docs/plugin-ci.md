## CI for Koha plugins via GitHub Actions + ktd

Plugin tests need a real Koha instance. Local dev runs via `koha-testing-docker`; CI needs the same setup, with caching so cold-cloning Koha and pulling ktd images don't dominate the wall clock.

`koha-plugin-staff-roster` runs four jobs on every push: build the frontend bundle, run the prove suite against Koha main inside ktd, and (on tags) package + release. Pattern below maps to commits `c326fa0`..`fbe33fb`.

### Jobs

```yaml
# .github/workflows/main.yml
name: CI

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
  # Manual fire from the Actions tab. release job stays gated on
  # refs/tags/v*, so dispatch only re-runs build + prove without
  # publishing a duplicate Release.
  workflow_dispatch:

jobs:
  build:
    name: Build frontend bundle
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - name: Cache bun install
        uses: actions/cache@v4
        with:
          path: ~/.bun/install/cache
          key: bun-${{ runner.os }}-${{ hashFiles('bun.lock') }}
          restore-keys: bun-${{ runner.os }}-
      - run: bun install --frozen-lockfile
      - run: bun run check
      - run: bun run build
      - uses: actions/upload-artifact@v4
        with:
          name: built-bundle
          path: |
            Koha/Plugin/<TLD>/<Org>/<Project>/staff-roster.js
            Koha/Plugin/<TLD>/<Org>/<Project>/staff-roster.css
          if-no-files-found: error
          retention-days: 7
```

`build` runs first so the bundle artifact is available to `prove` (REST tests against a freshly-installed plugin need the matching JS bundle in place if any spec exercises the rendered shell).

### Caching strategy

Three caches, each tuned to a different refresh cadence:

```yaml
- name: Compute Koha cache key
  id: cache-key
  run: |
    WEEK=$(date -u +%Y-%U)
    echo "week=$WEEK" >> "$GITHUB_OUTPUT"

- name: Cache Koha clone
  id: koha-cache
  uses: actions/cache@v4
  with:
    path: kohaclone
    key: koha-main-${{ steps.cache-key.outputs.week }}
    restore-keys: koha-main-

- name: Cache ktd images
  id: ktd-image-cache
  uses: actions/cache@v4
  with:
    path: ~/ktd-images.tar.gz
    key: ktd-images-${{ steps.cache-key.outputs.week }}
    restore-keys: ktd-images-
```

- **Bun install cache** — keyed by `bun.lock` hash. Refreshes whenever a dep is added.
- **Koha clone cache** — keyed by ISO week (`%Y-%U`). Refreshes weekly so CI picks up Koha main movement without re-cloning per push. Cache miss falls back to a fresh shallow clone; cache hit pulls the latest tip.
- **ktd image cache** — keyed by ISO week, stored as a single `docker save` tarball. Loading a tarball is ~3 min faster than a registry pull on cold runners.

The week-keyed caches both fall through to a `restore-keys: <prefix>-` pattern, so the previous week's snapshot is loaded as a starting point and only the diff is fetched. Bandwidth-friendly.

### Refreshing within a cache hit

A weekly cache key is good for stability but bad for catching breakage that lands mid-week. Refresh inside the cached clone on every cache-hit run:

```yaml
- name: Clone Koha main (cache miss / refresh)
  if: steps.koha-cache.outputs.cache-hit != 'true'
  run: |
    rm -rf kohaclone
    git clone --branch main --single-branch --depth 1 \
      https://github.com/Koha-Community/Koha.git kohaclone

- name: Refresh shallow clone (cache hit, but pull main tip)
  if: steps.koha-cache.outputs.cache-hit == 'true'
  working-directory: kohaclone
  run: |
    git fetch --depth 1 origin main
    git reset --hard origin/main
```

The shallow refresh is cheap (single commit, single object) but keeps the suite running against today's `main` even on a Friday afternoon push.

### Spinning up ktd

ktd's compose template reads several variables from the environment. Without them the koha service tries to bind-mount empty paths and exits with `invalid spec: :/kohadevbox/koha`:

```yaml
- name: Fetch ktd compose + defaults
  run: |
    sudo sysctl -w vm.max_map_count=262144   # ES needs this on GH runners
    wget -q -O docker-compose.yml \
      https://gitlab.com/koha-community/koha-testing-docker/raw/main/docker-compose.yml
    mkdir -p env
    wget -q -O env/defaults.env \
      https://gitlab.com/koha-community/koha-testing-docker/raw/main/env/defaults.env
    cp env/defaults.env .env
    {
      echo "SYNC_REPO=${GITHUB_WORKSPACE}/kohaclone"
      echo "LOCAL_USER_ID=$(id -u)"
      echo "KOHA_IMAGE=main"
      echo "KOHA_INTRANET_URL=http://127.0.0.1:8081"
      echo "KOHA_MARC_FLAVOUR=marc21"
      echo "RUN_TESTS_AND_EXIT=no"
    } >> .env
```

`vm.max_map_count=262144` is the documented Elasticsearch requirement on Linux runners — without it ES inside the koha service crashes, and Plack startup times out waiting for it.

`SYNC_REPO=${GITHUB_WORKSPACE}/kohaclone` is the load-bearing piece: it tells ktd to bind-mount your cached Koha clone as `/kohadevbox/koha` inside the container, so the suite runs against today's main rather than whatever was baked into the image.

### Polling the ready signal

Don't trust Plack's logs to know when ktd is up — Starman writes to different paths depending on Koha build, and `koha-mysql` races the koha-create instance setup. The ktd entrypoint emits a stable line as the last step of bootstrap; poll for that:

```yaml
- name: Wait for ktd ready signal
  run: |
    # ktd's entrypoint emits this exact line as the last step of its
    # bootstrap, after koha-create + plack + zebra + workers are all
    # live. 240 * 5s = 20 min ceiling for the rare slow runner.
    for i in $(seq 1 240); do
      if docker compose -p koha logs koha 2>&1 | grep -q "koha-testing-docker has started up"; then
        echo "Koha ready after ${i} polls (~$((i*5))s)"
        break
      fi
      if [ "$i" = "240" ]; then
        echo "Timed out waiting for ktd ready signal"
        docker compose -p koha logs koha | tail -200
        exit 1
      fi
      sleep 5
    done
```

20 minutes is generous; cold runs typically clear the gate in 5–8 minutes. The `tail -200` on timeout dumps enough log to diagnose without cluttering normal runs.

### Running the suite

```yaml
- name: Sync plugin into the container
  working-directory: plugin
  run: |
    docker exec koha-koha-1 rm -rf /var/lib/koha/kohadev/plugins/Koha /var/lib/koha/kohadev/plugins/t
    docker cp Koha koha-koha-1:/var/lib/koha/kohadev/plugins/Koha
    docker cp t    koha-koha-1:/var/lib/koha/kohadev/plugins/t

- name: Run prove suite
  run: |
    docker exec koha-koha-1 sh -c '
      cd /var/lib/koha/kohadev/plugins &&
      KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml \
        prove t/00-load.t t/rrule.t t/self_service.t t/swap_ownership.t \
              t/swap_respond.t t/exceptions.t t/additional_fields.t \
              t/conflict_check.t t/visibility.t
    '

- name: Tear down
  if: always()
  run: docker compose -p koha down --volumes
```

Same `docker cp` after `rm -rf` trap as the local dev / cypress workflows: `docker cp src target` nests when target exists. Always remove first.

`if: always()` on tear-down ensures volumes are cleared even when the suite fails — important on self-hosted runners where leftover state pollutes subsequent runs.

### Releasing on tag

```yaml
release:
  name: Package + GitHub Release
  runs-on: ubuntu-latest
  if: startsWith(github.ref, 'refs/tags/v')
  needs: [build, prove]
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v4
    - uses: oven-sh/setup-bun@v2
    - uses: extractions/setup-just@v3
    # ... carton install, just package, gh release create ...
```

`if: startsWith(github.ref, 'refs/tags/v')` keeps the release job dormant on `workflow_dispatch` and `pull_request`. Manual dispatch from the Actions UI re-runs `build` + `prove` for confidence, never publishes a duplicate release.

`needs: [build, prove]` makes the release wait for both — if prove fails on a tag push, the release doesn't ship.

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Skipping `vm.max_map_count` | ES crashes silently inside ktd, Plack never starts | `sudo sysctl -w vm.max_map_count=262144` before `compose up` |
| Polling Plack logs for readiness | False positive on partial bootstrap | Grep ktd's own ready signal: `koha-testing-docker has started up` |
| `docker cp` without `rm -rf` first | Files nest inside `Koha/Koha/...`, plugin doesn't load | Remove the target dir before copying |
| Caching ktd images by image SHA | Cache invalidates on every upstream rebuild | Key by ISO week, refresh on cache miss |
| Shallow clone with `git pull` | Cache-hit refresh fails on diverged history | `git fetch --depth 1 && git reset --hard origin/main` |
| Tagging with `release` job hooked to push | Manual workflow dispatch re-publishes | `if: startsWith(github.ref, 'refs/tags/v')` |
| Fixed timeout instead of poll loop | Slow runners flake | 240×5s poll loop with explicit log dump on timeout |
| Forgetting `if: always()` on teardown | Failed runs leak volumes | Tear down unconditionally |

### Where native integration would help

- A reusable GitHub Action (`koha-community/setup-ktd@v1`) wrapping the compose download + env injection + ready-signal poll, so every plugin's CI shrinks to two steps.
- A `koha-plugin add ci` scaffold that drops a parametrised `main.yml` matching this pattern.
- ktd publishing a `latest-stable` image tag so cache keys stop drifting weekly without sacrificing freshness.
