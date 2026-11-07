# Security

envsetup runs with your user's rights.
It also uses sudo to install packages.
So a bug in envsetup can harm your machine.

## Supported releases

Only the newest release gets security fixes.
Each fix comes in a new release.
To get the fix, run `envsetup update` or the install command from the README again.
If you set `ENVSETUP_VERSION`, set it to the fixed release.

## Report a problem

An attacker may be able to use a bug that you find.
Examples are a download that envsetup does not check, or a repo or config that runs code it should not.
Please report such a bug privately.
Please do not open a public issue for it.

To report it, open [a private report](https://github.com/hunterdw0007/envsetup/security/advisories/new).
You can also select **Security > Report a vulnerability** on the repo's GitHub page.
Only you and the maintainer can see the report.

Describe the bug and the steps that show it.
Name the release and the Linux system that you used.

## After you report

1. The maintainer replies in the report.
2. The maintainer checks the bug and may ask you questions.
3. If the maintainer confirms the bug, a new release fixes it.
4. The maintainer may then publish the report as a security advisory.

An advisory is a public notice of the bug and its fix.
The advisory names you, unless you ask the maintainer not to.
