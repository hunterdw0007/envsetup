# What your shell gets

This page lists what envsetup adds to your shell.
"Work lite" means the `work` profile in `lite` mode.

## Startup files

**Link shell config** adds a block to your shell startup files.
That block loads `shell/init.sh` in each new shell.
`shell/init.sh` loads the shared config and then your profile's config.

**Link shell config** always changes `~/.bashrc`.
It also changes the startup file of your login shell:

- `~/.zshrc` if your login shell is zsh
- `~/.bash_profile` if your login shell is bash on macOS

zsh is optional.
**Set up zsh + oh-my-zsh** installs zsh and [oh-my-zsh](https://ohmyz.sh) if they are missing.
It offers to make zsh your login shell.
It also adds the envsetup block to `~/.zshrc`.
To include this action in **Link shell config** and **Run everything**, set `ENVSETUP_SHELL=zsh` in `config.sh`.

## Which shells get what

Interactive shells get the most.
Every profile gets the prompt, the aliases and the tool hooks.
Every profile except work lite also gets the environment variables and the functions.

A non-interactive shell gets less.
Examples are `ssh host cmd`, `scp`, `rsync` and scripts.
A non-interactive shell gets only these things:

- Homebrew on `PATH`, on macOS
- the environment variables, except on work lite
- the variables for dotfiles that envsetup moved to XDG folders
- your `config.sh`

A non-interactive shell does not get the tool hooks.
So tools that mise installs are not on `PATH` there.
To fix this, add `eval "$(mise activate bash --shims)"` to `config.sh`.

## Prompt

The prompt is for bash.
In zsh, the oh-my-zsh theme sets the prompt instead.

The prompt shows these things in order:

1. the time
2. the Kubernetes context
3. a short path, for example `~/d/envsetup`
4. the git branch, and how many commits it is ahead of or behind its remote
5. `❯` on its own line

envsetup sets the prompt from `PROMPT_COMMAND`.
It adds to any `PROMPT_COMMAND` that you already have.
The prompt reads the Kubernetes context and the git branch from their files.
It saves the context in `~/.cache/envsetup` until your kubeconfig changes.
So the prompt runs only one program: one `git` command inside a repo.

## Aliases

- `ls` shows colors.
- `la` and `ll` list files in more detail.
- `..`, `...` and `....` go up one, two or three folders.
- `cat` and `less` use `bat` if you have `bat`.
- The `work` profile also adds kubectl aliases, for example `kc` and `kcaMem`.

## Tool hooks

envsetup adds a hook for each of these tools that you have:

- `direnv` loads `.envrc` files.
- `zoxide` adds the `z` command.
- `fzf` adds key bindings: Ctrl-R for history, Ctrl-T for files and Alt-C to change folders.
- `mise` sets the runtime versions for each project.

On Debian and Ubuntu, `fd` runs `fdfind`.
On macOS, envsetup puts Homebrew and its tools on `PATH` if your shell does not.

## Environment variables

envsetup sets these environment variables:

- the XDG base folder variables
- `EDITOR=vim`
- a `MANPAGER` that shows man pages with `bat`, if you have `bat`

Each value is only a default.
You can set one of these variables before the envsetup block.
For example, set it in `~/.profile` or earlier in your startup file.
Then envsetup keeps your value.

## Functions

The functions work in bash, including bash 3.2 on macOS.
They help you work with a folder that contains many git repos.

| Function | Short name |
| --- | --- |
| `branchAll` | `ba` |
| `fetchAll` | `fa` |
| `pullMainAll` | `pma` |
| `mainOriginAll` | |
| `pruneBranches` | `pb` |
| `pruneBranchesAll` | `pba` |

`pruneBranches` and `pruneBranchesAll` list old branches first.
They ask before they delete a branch.
They keep unmerged branches unless you add `--force`.
Most functions accept `--help`.

The `work` profile also adds `resetNode` for Helm charts.

## Colors

The functions come with `shell/shared/colors.sh`.
That file sets color variables for your interactive shell and for `config.sh`.
For example, `echo -e "${RED}text${RESET}"` prints red text.
Run `show_colors` to see every color.

envsetup does not export the color variables.
So a script that you run does not get them.
Each value is only a default.
If you set a variable with the same name before the envsetup block, envsetup keeps your value.

## Git settings

`git/gitconfig` holds envsetup's git aliases and settings.
**Configure git** installs them.
The git aliases are git commands, for example `git s`, `git d` and `git l`.
They are not shell aliases.

Some settings change what git does by default:

- `pull.rebase = true`: `git pull` rebases your commits. It does not merge.
- `fetch.all = true`: each fetch gets every remote.
- `fetch.prune = true`: each fetch removes remote branches that the remote deleted. Local tags stay.
- `push.default = current`: `git push` pushes the current branch to a branch with the same name.
- `status.showUntrackedFiles = all`: `git status` lists every untracked file, also inside new folders.
- `credential.helper = cache --timeout=3600`: git keeps HTTPS passwords in memory for one hour.
- `git p`, `git pf` and `git su` expect a remote named `origin` and a branch named `main`.
- `git aa` runs `git add .`. It adds every file that `.gitignore` does not exclude, for example an `.env` file.

On macOS or WSL, you can use the operating system's credential helper instead.
`config.example.sh` shows how.

To change a setting, add your own value to `ENVSETUP_GIT_CONFIG` in `config.sh`.
For example, add `"pull.rebase=false"`.
Then run **Configure git** again.
