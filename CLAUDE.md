# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Docker image that compiles Firebird SQL Server 2.5.9 **from source** so it runs on ARM64/aarch64.
There is no application code — the entire repo is one `Dockerfile` plus three shell scripts. Any change is
either a build-time change (`build.sh`) or a runtime change (`docker-entrypoint.sh`, `docker-healthcheck.sh`).

Derived from [jacobalberty/firebird-docker](https://github.com/jacobalberty/firebird-docker).

## Commands

```bash
# Build (the only build step; ~3 min, source compile happens in one RUN layer)
docker build -t firebird .

# Build ignoring cache — required to actually re-verify build.sh, since the
# whole compile is one cached layer keyed on build.sh's contents
docker build --no-cache --progress=plain -t firebird .

# Run with a known password and an auto-created database
docker run -d --name fbtest -e ISC_PASSWORD=testpw -e FIREBIRD_DATABASE=test.fdb -p 3050:3050 firebird

# Verify the image works (there is no test suite — this is the smoke test)
docker inspect --format '{{.State.Health.Status}}' fbtest      # -> healthy
docker exec fbtest sh -c "echo 'SELECT 1 FROM rdb\$database;' | \
  /usr/local/firebird/bin/isql -u SYSDBA -p testpw /firebird/data/test.fdb"
```

Healthcheck startup takes ~30-45s. If the container exits immediately, read `docker logs` — the entrypoint
does first-run database setup before exec'ing `fbguard`.

There is no test framework, linter, or dependency manifest. `.travis.yml` invokes `./travis.sh`, **which does
not exist in this repo** — CI is vestigial and does not run.

## Architecture

### The `skel` indirection (most important thing to understand)

`configure` is told to put the security database and config files *inside the `/firebird` volume*
(`--with-fbsecure-db=${VOLUME}/system`, `--with-fbconf=${VOLUME}/etc`). But `/firebird` is declared as a
`VOLUME`, so at runtime a fresh mount **shadows** whatever the build wrote there. The last three lines of
`build.sh` therefore move those artifacts out to `${PREFIX}/skel/`, and `docker-entrypoint.sh` copies them
back into the volume on first run if absent.

This is a contract spanning three files. If you change any `--with-fb*` path in `build.sh`, check whether it
lands under `${VOLUME}` and whether the skel stash + entrypoint restore need updating too.

### Scripts depend on Dockerfile `ENV`

`build.sh` and `docker-entrypoint.sh` are not standalone — they read `PREFIX`, `VOLUME`, `FBURL`, and `DBPATH`
from the Dockerfile's `ENV`. Running either directly on a host will misbehave or damage it.

### One-layer install-build-purge

`build.sh` apt-installs toolchain + dev headers, compiles, then `apt-get purge`es the build deps, all inside a
single `RUN` so nothing is retained in the layer. Consequence: when adding a package, decide deliberately
whether it belongs in **both** lists (build-only) or **only the install list** (runtime dep). Runtime deps that
must survive: `netcat`, `libncurses5`, `libtommath1`, `libicu57`, `libedit2`. Purging a runtime dep produces an
image that builds green and then fails to start.

### Entrypoint SQL accumulator

`docker-entrypoint.sh` builds up a multi-statement script in the `$isql` variable via `build isql "<stmt>"`,
then pipes it to `isql` once via `run isql`. First-run work (SYSDBA password via `gsec`, optional
`FIREBIRD_USER`/`FIREBIRD_DATABASE` creation) is guarded on the absence of `security2.fdb` / the database file,
so restarts are idempotent. The script ends with `$@`, which execs the `CMD` (`fbguard`).

Generated passwords are written to `/firebird/etc/SYSDBA.password`, which is a **sourced shell file** that the
entrypoint reads back with `read_var`.

### Healthcheck escalation

Default is a bare `nc -z 127.0.0.1 3050` port probe. If `/firebird/etc/docker-healthcheck.conf` exists and
defines `HC_USER`/`HC_PASS`/`HC_DB`, it instead runs a real `SHOW DATABASE` query. That conf file is `source`d,
so it executes as shell.

## Build fragility — read before touching `build.sh`

This image is pinned to EOL software and the build has already broken once from external drift. Constraints
that exist for a reason:

- **`debian:stretch` is EOL.** apt must point at `archive.debian.org`. `stretch-updates` no longer exists in
  the archive (it was deleted on archival) and must not be listed. `Acquire::Check-Valid-Until "false"` is
  required because archived `Release` files are years past expiry.
- **`config.guess`/`config.sub` are replaced from the `autotools-dev` package.** Firebird 2.5.9's bundled
  copies predate aarch64 and cannot detect this host, so this replacement is load-bearing for ARM64. Do not
  restore the old `git.savannah.gnu.org` downloads: gitweb now 502s and cgit is rate-limited (it has failed
  builds with `curl: (52) Empty reply from server`).
- **Use `curl -f` for every download.** Without it curl writes the HTTP error page into the target file and
  exits 0, turning an upstream outage into a confusing `configure` failure much later.
- **`CXXFLAGS="-std=gnu++98"`** is what lets 2.5.9's ancient sources compile under stretch's GCC 6. Bumping the
  base image is not a small change — modern GCC will not build this source tree as-is.

## README is inherited and overstates this image

`README.md` came from upstream and documents behaviour that is **not implemented here**. Verified absent from
all scripts: `TZ`, `EnableLegacyClientAuth`, `EnableWireCrypt`, `RemoteAuxPort`, and the SC/SS/CS server
architecture selection. It also discusses Firebird 3.0/4.0 while this Dockerfile pins 2.5.9. Treat the
scripts as truth; don't cite the README as evidence a feature exists.

Actually implemented: `ISC_PASSWORD`, `FIREBIRD_DATABASE`, `FIREBIRD_USER`, `FIREBIRD_PASSWORD`, and the
`<VARIABLE>_FILE` indirection for those (via `file_env`).

## Repo note

The `origin` remote URL has a GitHub personal access token embedded in it in plaintext. Avoid echoing
`git remote -v` output, and scrub `github_pat_*` from anything you paste back.
