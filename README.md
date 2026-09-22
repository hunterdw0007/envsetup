# envsetup

A [gum](https://github.com/charmbracelet/gum)-powered TUI for getting a new or wiped machine
back to a working shell: aliases, exports, functions, and your usual CLI tools.

## Usage

```sh
git clone <this repo> ~/envsetup
cd ~/envsetup
./setup.sh
```

From the menu you can:

- pick a machine profile (`work` or `home`)
- for `work`, also pick a mode: `full` assumes sudo access and does everything below;
  `lite` assumes no sudo access, so it only loads the prompt (`ps1.sh`) and aliases and
  skips package installs entirely
- link `shell/init.sh` into your `~/.bashrc` / `~/.zshrc`, which loads shared config plus
  the active profile's overlay
- install the packages listed for `common` + the active profile (skipped for `work` lite)

`setup.sh` will try to install `gum` itself (via `brew` or `go install`) if it isn't found.

## Layout

```
shell/
  shared/            # ps1, aliases, exports, functions loaded on every machine
                      # (work/lite only loads ps1 + aliases)
  profiles/
    work/            # overlays loaded only when profile = work
    home/            # overlays loaded only when profile = home
  init.sh            # sourced from your rc file; wires the above together
packages/
  common.txt         # packages installed everywhere
  work.txt           # extra packages for the work profile
  home.txt           # extra packages for the home profile
```

Edit the files under `shell/` and `packages/` to match what you actually use — the shipped
content is just a starting point. Package names are passed straight to whichever of
`apt`/`dnf`/`brew`/`pacman` is detected on the machine.
