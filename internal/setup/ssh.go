package setup

import (
	"os"
	"strings"
)

// gitSigns reports whether git already has a signing key or already signs commits (envsetup::git_signs).
// GPG signing is an example.
// envsetup then leaves signing alone, so it never replaces the user's own settings.
func (s *Setup) gitSigns() bool {
	return s.gitGlobal("user.signingkey", false)+s.gitGlobal("commit.gpgsign", false) != ""
}

// hostname returns $HOSTNAME as bash sets it.
// bash keeps an inherited HOSTNAME, and otherwise asks the kernel.
func hostname() string {
	if h, ok := os.LookupEnv("HOSTNAME"); ok {
		return h
	}
	h, _ := os.Hostname()
	return h
}

// SetUpSSHKey creates this machine's SSH key once (envsetup::set_up_ssh_key).
// It then offers to add the key to GitHub and to sign git commits with it.
// It needs no sudo, so work lite runs it too.
func (s *Setup) SetUpSSHKey() error {
	key := s.Home + "/.ssh/id_ed25519"
	const url = "https://github.com/settings/keys"
	// GitHub advises one key per machine.
	// The comment names the machine in a list of keys.
	user, err := s.Output("id", "-un")
	if err != nil {
		return err
	}
	comment := user + "@" + hostname()
	if _, err := os.Stat(key); err == nil {
		s.Warn("An SSH key already exists: " + key)
		return nil
	}
	if !HasCmd("ssh-keygen") {
		s.Fail("This machine has no ssh-keygen. Install openssh-client. Then run Set up SSH key again.")
		return ErrFailed
	}
	if s.DryRun {
		s.Would("create the SSH key " + key + " (" + comment + ")")
		s.Would("let ssh-keygen ask for a passphrase")
		if HasCmd("gh") {
			s.Would("ask to add it to your GitHub account with gh")
		} else {
			s.Would("show the public key, to add at " + url)
		}
		if !s.gitSigns() {
			s.Would("ask to sign your git commits with it")
			if HasCmd("gh") {
				s.Would("add it to your GitHub account as a signing key with gh, if you say yes to both questions")
			} else {
				s.Would("show where to add it as a signing key, if you say yes to signing: " + url)
			}
		}
		return nil
	}

	if !isDir(s.Home + "/.ssh") {
		if err := os.Mkdir(s.Home+"/.ssh", 0o700); err != nil {
			return err
		}
		if err := os.Chmod(s.Home+"/.ssh", 0o700); err != nil { // like mkdir -m, the mode ignores the umask
			return err
		}
	}
	// ssh-keygen asks for the passphrase itself.
	// So the passphrase never shows in a process list.
	if err := s.Run("ssh-keygen", "-t", "ed25519", "-C", comment, "-f", key); err != nil {
		return err
	}
	// The marker lets uninstall offer to delete only a key that envsetup created.
	if err := makeMarker(s.SSHMarker); err != nil {
		return err
	}
	s.Success("Created the SSH key " + key)

	// After a no here, the step also uploads no signing key below.
	useGH := false
	if HasCmd("gh") {
		useGH, _ = s.UI.Confirm("Add the key to your GitHub account with gh?", false)
	}
	// gh fails when it has no login or no admin:public_key scope.
	// The step then shows the key instead.
	if useGH && s.Run("gh", "ssh-key", "add", key+".pub", "--title", comment) == nil {
		s.Success("Added the key to your GitHub account")
	} else {
		pub, _ := os.ReadFile(key + ".pub")
		s.Say("Add this public key at "+url+":", strings.TrimRight(string(pub), "\n"))
	}

	if s.gitSigns() {
		s.Warn("git already has signing settings, so envsetup leaves them as they are.")
		return nil
	}
	if yes, _ := s.UI.Confirm("Sign your git commits with this key?", false); !yes {
		return nil
	}
	for _, kv := range [][2]string{{"gpg.format", "ssh"}, {"user.signingkey", key + ".pub"}, {"commit.gpgsign", "true"}} {
		if err := s.Run("git", "config", "--global", kv[0], kv[1]); err != nil {
			return err
		}
	}
	s.Success("git now signs your commits with " + key)
	// GitHub marks a signed commit "Verified" only when it has the key as a signing key.
	// gh exits 0 when GitHub already has the key.
	// gh fails without the admin:ssh_signing_key scope.
	// The step then says where to add the key instead.
	if useGH && s.Run("gh", "ssh-key", "add", key+".pub", "--type", "signing", "--title", comment+" signing") == nil {
		s.Success("Added the key to your GitHub account as a signing key")
	} else {
		s.Warn(`Add the public key as a signing key at ` + url + ` (key type "Signing Key")`)
	}
	return nil
}
