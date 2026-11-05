#!/usr/bin/env bash
# This fake ssh-keygen is for the tests.
# smoke.sh and distros/ copy it onto PATH as `ssh-keygen`.
# It writes the key pair that -f and -C name.
# It asks for no passphrase.
# It logs each call to $SMOKE_LOG.

echo "ssh-keygen $*" >>"$SMOKE_LOG"
while (($#)); do
	case $1 in
	-C) comment=$2 ;;
	-f) file=$2 ;;
	esac
	shift
done
echo smoke-private-key >"$file"
echo "ssh-ed25519 AAAAsmoke $comment" >"$file.pub"
