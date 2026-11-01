# Contributing

[`AGENTS.md`](AGENTS.md) sets the rules for this repo.
It covers commit messages, branches, code style, releases and tests.
This page gives an overview.

## Layout

```
install.sh           # the curl | bash script: downloads a release to a temp folder, runs setup.sh, deletes it
setup.sh             # the gum menu: profile and mode, linking, package installs
lib/                 # the menu's actions; lib/config.sh loads the defaults, then the user's config.sh
config.example.sh    # template for ~/.config/envsetup/config.sh
AGENTS.md            # the rules for this repo
CHANGELOG.md         # the changes in each release (CI writes it)
docs/                # user docs that the README links to
tests/               # smoke.sh and release.sh (CI), distros/ and macos.sh (manual)
shell/
  shared/            # prompt, aliases, tool hooks, environment variables and functions
                     # for every machine (work lite loads only the prompt, aliases and
                     # tool hooks), plus colors.sh and Homebrew's PATH on macOS
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

CI runs `shellcheck` on every shell script and checks that they parse under macOS's bash 3.2.
It also runs `tests/smoke.sh` and `tests/release.sh`.
To run them on your machine:

```sh
shellcheck setup.sh                    # or any other script
docker run --rm -t -v "$PWD:/src:ro" ubuntu:24.04 bash /src/tests/smoke.sh
tests/release.sh                       # needs commitizen's cz on PATH
```

The Testing section of `AGENTS.md` has the details.

Two more tests run real installs.
They take too long for CI, so you run them yourself.

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

### Test on macOS

`tests/macos.sh` runs on a Mac and does not change it.
It checks these things:

- `install.sh`, and `setup.sh` under macOS's bash 3.2
- the switch to Homebrew's bash
- **Run everything** for home, work full and work lite, each in a temporary `$HOME`
- every installer
- whether zsh, login bash and Homebrew's bash load envsetup
- uninstall

A script selects the options in gum's menu.
The test records `brew install` and `chsh` commands instead of running them.
It runs every other brew command for real.
So the test also checks that Homebrew has every formula that envsetup uses.

```sh
tests/macos.sh
```

The test uses the commit that you have checked out.
It writes `macos-report/<time>/report.md`, with logs next to it.

The `macos` workflow runs the test on GitHub's macOS runners.
The run summary then shows the report.
macOS runners start slowly, and the test takes a few minutes.
So the workflow runs only when you ask for it.
Open the Actions tab, then "macos", then "Run workflow".
Or add the `macos` label to a PR.
The label runs the test again on every push to that PR.
