# Security

envsetup runs with your user's rights.
It also uses sudo to install packages.
So a bug in envsetup can harm your machine.

An attacker may be able to use a bug that you find.
Examples are a download that envsetup does not check, or a repo or config that runs code it should not.
Please report such a bug privately.
On this repo's GitHub page, select **Security > Report a vulnerability**.
Please do not open a public issue for it.

Only the newest release gets security fixes.
Each fix comes in a new release.
