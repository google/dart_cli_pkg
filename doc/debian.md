This task updates an existing Debian PPA repository with the latest `.deb` files for this package in both `x64` and `ia32` architectures. It's enabled by calling `pkg.addDebianTasks()`.

By default, the task assumes that the GPG key for signing the PPA repository is already imported. If `pkg.gpgPrivateKey` is set, then it imports the GPG key and also sets the GPG fingerprint while importing the key.

This task assumes that the PPA repository is on GitHub (specifically to [`pkg.githubRepo`][]), and that the task is running in a clone of that GitHub repo.

[`pkg.githubrepo`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubRepo.html

## Usage

To publish the debian packages on the PPA repository hosted on GitHub Pages,

1. Create a repository on GitHub to host as the PPA repository. Setup instructions can be found [here](https://assafmo.github.io/2019/05/02/ppa-repo-hosted-on-github.html).
2. Place the control file for the Debian packages in the PPA repository. Set the `pkg.debianControlPath` with the path to this file. The above two steps are to be performed for the initial setup only.
3. Set the configuration variables for the task. If the GPG key is already present on the system, do not set the `pkg.gpgPrivateKey`.
4. Use the `pkg.addDebianTasks()` to add the Debian task to Grinder.

## `pkg-debian-update`

Uses configuration: [`pkg.version`][], [`pkg.humanName`][], [`pkg.botName`][],
[`pkg.botEmail`][], [`pkg.githubRepo`][], [`pkg.githubUser`][],
[`pkg.githubPassword`][], [`pkg.debianRepo`][], [`pkg.debianControlPath`][],
[`pkg.gpgFingerprint`][], [`pkg.gpgPassphrase`][], [`pkg.gpgPrivateKey`][]

[`pkg.version`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/version.html
[`pkg.humanname`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/humanName.html
[`pkg.botname`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/botName.html
[`pkg.botemail`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/botEmail.html
[`pkg.githubuser`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubUser.html
[`pkg.githubpassword`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/githubPassword.html
[`pkg.debianrepo`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/debianRepo.html
[`pkg.debiancontrolpath`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/debianControlPath.html
[`pkg.gpgfingerprint`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/gpgFingerprint.html
[`pkg.gpgprivatekey`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/gpgPrivateKey.html
[`pkg.gpgpassphrase`]: https://pub.dev/documentation/cli_pkg/latest/cli_pkg/gpgPassphrase.html

Checks out [`pkg.debianRepo`][] and pushes a commit updating the repository with the latest packages.
