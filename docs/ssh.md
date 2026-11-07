# SSH key

**Set up SSH key** creates one SSH key for this machine, so `git clone git@...` works.
If `~/.ssh/id_ed25519` exists, the action changes nothing.
Otherwise, `ssh-keygen` asks for a passphrase.
You can leave the passphrase empty.
The key comment is `<user>@<hostname>`, so you can find the key in a list of keys.

## Add the key to GitHub

If `gh` is installed, the action offers to add the key to your GitHub account.
A scope is a permission that you give `gh` when you log in.
`gh` needs the `admin:public_key` scope for this: `gh auth refresh -s admin:public_key`.
If `gh` is missing, you say no, or the upload fails, the action shows the public key.
Then add the public key at <https://github.com/settings/keys>.

## Sign your commits

The action also offers to sign your git commits with the key.
It skips this offer if git already has `user.signingkey` or `commit.gpgsign`.
If you say yes to both offers, the action also adds the key to GitHub as a signing key.
GitHub then shows a signed commit as "Verified" if its email is verified on your GitHub account.
`gh` needs the `admin:ssh_signing_key` scope for this: `gh auth refresh -s admin:ssh_signing_key`.
If the action does not add the signing key, add the public key at <https://github.com/settings/keys>.
Choose the key type **Signing Key** there.

## Uninstall and work lite

Uninstall asks before it deletes the key.
Uninstall does not remove the key from your GitHub account.
Work lite installs no packages, so it needs `ssh-keygen` from the system's `openssh-client` package.
