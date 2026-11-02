# Contributing

[`AGENTS.md`](AGENTS.md) sets the rules for this repo.
It covers commit messages, branches, code style, releases and tests.
This page lists the requirements and goals of envsetup.
It also gives an overview of the repo.

## Requirements

Every change must keep these requirements true.
To break a requirement, first change it in its own PR.
Requirement 2 holds after [#104](https://github.com/hunterdw0007/envsetup/issues/104).

1. **Linux only.**
   envsetup supports the Linux systems in the README table, including WSL.
2. **Nothing to install first.**
   A machine with bash, curl and git can run envsetup.
   gum is the only exception.
   envsetup installs gum, and tar and gzip if gum needs them, before the menu opens.
3. **Same release, same result.**
   A second run of the same release with the same `config.sh` changes nothing.
4. **No change without a choice.**
   envsetup changes nothing until the user selects an action.
5. **A preview for each change.**
   A dry run shows each change and makes none.
6. **A full uninstall.**
   Uninstall removes everything that envsetup created.
   Uninstall asks before it removes anything that belongs to the user.
7. **Only the shell config stays.**
   After a run, the machine keeps only the shell config, the user's files and the files that envsetup created.
8. **Pinned and checked downloads.**
   Each download has a pinned version and a checksum.
   envsetup never downloads "latest" during a run.
9. **No root for the shell config.**
   The shell config and git settings work without sudo.
   Only packages and installers use root.
10. **User files in one place.**
    The user's files live only in `~/.config/envsetup`.
    An update never changes them.
11. **No lost user files.**
    envsetup asks before it deletes or replaces a user file.
12. **One failure stops one step.**
    A failed step shows its error.
    The other steps still run.
13. **Clear choices.**
    Each menu choice says what it does on this machine.
14. **Breaking changes come first.**
    The changelog lists each breaking change first, under "Breaking changes".

## Goals

New work moves envsetup toward these goals.

- **Easy to set up for each user.**
  Each user can change envsetup for their own needs.
  A user can paste their own settings and shell code from the menu.
  [#105](https://github.com/hunterdw0007/envsetup/issues/105) and [#106](https://github.com/hunterdw0007/envsetup/issues/106) track this.
- **Fast shell start.**
  The shell config adds less than 50 ms to each new shell.
  It makes no network calls.
- **Runs without a person.**
  Each action can run from options, without the menu.
  [#42](https://github.com/hunterdw0007/envsetup/issues/42) tracks this.
- **Tested on each supported system.**
  The tests cover each system in the README table.

## Layout

```
install.sh           # the curl | bash script: downloads a release to a temp folder, runs setup.sh, deletes it
setup.sh             # the gum menu: profile and mode, linking, package installs
lib/                 # the menu's actions; lib/config.sh loads the defaults, then the user's config.sh
config.example.sh    # template for ~/.config/envsetup/config.sh
AGENTS.md            # the rules for this repo
CHANGELOG.md         # the changes in each release (CI writes it)
docs/                # user docs that the README links to
tests/               # smoke.sh and release.sh (CI), distros/ (manual)
shell/
  shared/            # prompt, aliases, tool hooks, environment variables and functions
                     # for every machine (work lite loads only the prompt, aliases and
                     # tool hooks), plus colors.sh
  profiles/
    work/            # config for the work profile only
    home/            # config for the home profile only
  init.sh            # your startup file loads this file, and this file loads the rest
packages/
  common.txt         # packages for every profile
  work.txt           # extra packages for the work profile
  home.txt           # extra packages for the home profile
  names.txt          # package names that differ from Debian's, for each package manager
installers/
  common/            # scripts for every profile (none yet, so the folder does not exist)
  work/              # scripts for the work profile, in full mode only
  home/              # scripts for the home profile only
  extras/            # scripts that users select with ENVSETUP_EXTRAS
  versions.txt       # the version and sha256 of each download (bump-versions.sh writes it)
git/
  gitconfig          # default git aliases and settings, with no name or email
```

The package lists use Debian and Ubuntu names.
`packages/names.txt` lists the names that other package managers use instead.
Users change packages in `config.sh`, not in these files.

## Add an installer

Package managers do not have some tools, for example `terraform`, `kubectl` and `awscli`.
You can also use an installer for any other setup step, for example to clone a repo.
Installers go in `installers/`:

1. Add a script at `installers/common/<name>.sh` for every profile.
   Or add it at `installers/<profile>/<name>.sh` for one profile.
2. Make the script safe to run again.
   It must check whether the tool is already present.
   If so, it must exit before it does anything else.
   `installers/work/kubectl.sh` is an example.
3. The script runs in its own `bash` process.
   To use helpers like `envsetup::has_cmd`, source `$ENVSETUP_ROOT/lib/common.sh` in the script.
4. Check every download before you install or run it:
   - In this repo, pin the version and checksums in `installers/versions.txt`.
     Read them with `envsetup::pin`, like `kubectl.sh` does.
     `AGENTS.md` explains the rest.
   - In your own installers, use `envsetup::release_sha256` and `envsetup::install_release`.
     They work if the project publishes checksums.
   - Some projects only sign their releases.
     For those, keep the project's public key next to the script.
     Then call `envsetup::gpg_verify` with the key's fingerprint, like `awscli.sh` does.

**Run installers** runs each folder in order.
Inside a folder, it runs the scripts in alphabetical order.
If one script fails, the other scripts still run.
**Run installers** lists the failures at the end.

## Commits and releases

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org).
The commit types decide the next release number:

- `fix` adds a patch release, for example `v0.4.2` to `v0.4.3`.
- `feat` adds a minor release, for example `v0.4.2` to `v0.5.0`.
- A breaking change, for example `feat!:`, also adds a minor release before 1.0.0.
- From 1.0.0 on, a breaking change adds a major release.
- `docs`, `ci`, `test` and `chore` do not add a release.

CI makes the release after the checks on `main` pass.
CI adds the release to `CHANGELOG.md`, tags it and publishes it on GitHub.
[commitizen](https://commitizen-tools.github.io/commitizen/) does this work, with the settings in `.cz.toml`.
The Releases section of `AGENTS.md` has the details.

## Tests

CI runs `shellcheck` and `shfmt` on every shell script.
It also runs `tests/smoke.sh` and `tests/release.sh`.
To run them on your machine:

```sh
shellcheck setup.sh                    # or any other script
docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh
tests/release.sh                       # needs commitizen's cz on PATH
```

The Testing section of `AGENTS.md` has the details.

One more test runs real installs.
It takes too long for CI, so you run it yourself.

### Test on other distros

`tests/distros/run.sh` runs envsetup on about a dozen distros.
Each distro runs in a new container.
The distros are Ubuntu, Debian, Mint, Fedora, Alma, Rocky, Amazon Linux, Arch, openSUSE and Alpine.

The test replaces only gum's menu with a script.
It installs real packages and downloads real tools.
It runs as a user with sudo, not as root.
It checks these things:

- `install.sh` on a machine without git, and the gum install
- **Run everything** for home, work full and work lite
- which commands each run installed
- whether bash and zsh start without errors
- uninstall

Each distro takes a few minutes.
Run the test before you give a build to testers:

```sh
tests/distros/run.sh                               # every distro, 3 at a time
tests/distros/run.sh fedora:latest archlinux:latest
```

The test uses the commit that you have checked out.
It writes `distros-report/<time>/report.md`, with logs next to it.
The report has a pass or fail table and lists every problem.

You can also run the test from GitHub's Actions tab.
Open "distros" and select "Run workflow".
The run summary then shows the report.

Behind a proxy, set `DISTROS_PREHOOK` to a script that sets up the proxy in each container.
The top of `run.sh` explains how.
