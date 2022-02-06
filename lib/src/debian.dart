import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cli_pkg/src/standalone.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

import 'config_variable.dart';
import 'github.dart';
import 'info.dart';
import 'utils.dart';

/// The GitHub repository slug (for example, `username/repo`) of the PPA
/// repository for this package.
///
/// This must be set explicitly.
final debianRepo = InternalConfigVariable.fn<String>(
    () => fail("pkg.debianRepo must be set to deploy to PPA repository."));

/// The contents of the debian packages's control file.
///
/// By default, it is loaded from `control` at the root of the repository.
///
/// `cli_pkg` will automatically update the `version` field when building the package.
final debianControlData = InternalConfigVariable.fn<String>(() =>
    File("control").existsSync()
        ? File("control").readAsStringSync()
        : fail("pkg.debianControlData must be set to update Debian package."));

/// The fingerprint for GPG key to use when signing the release.
///
/// This is used to look up the GPG private key in the local machine's keystore
/// if [gpgPrivateKey] is unset.
///
/// By default, this comes from the `GPG_FINGERPRINT` environment variable.
final gpgFingerprint = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GPG_FINGERPRINT"] ??
    fail("pkg.gpgFingerprint must be set to deploy to PPA repository."));

/// The passphrase for the GPG key to use when signing the release.
///
/// By default, this comes from the `GPG_PASSPHRASE` environment variable.
final gpgPassphrase = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GPG_PASSPHRASE"] ??
    fail("pkg.gpgPassphrase must be set to deploy to PPA repository."));

/// The private key for the GPG key to use when signing the release.
///
/// If this is set, it's used to sign the release. Otherwise, a key is looked up
/// in the local system's key store using [gpgFingerprint].
final gpgPrivateKey = InternalConfigVariable.value<String?>(null);

/// Common GPG Arguments used while signing the release files
const List<String> _gpgArgs = [
  "--batch",
  "--pinentry-mode",
  "loopback",
  "--yes",
];

/// Whether [addDebianTasks] has been called yet.
var _addedDebianTasks = false;

/// Adds the task to create and upload the new package to the PPA.
void addDebianTasks() {
  if (!Platform.isLinux) {
    fail("Platform must be linux for this task.");
  }

  if (_addedDebianTasks) return;
  _addedDebianTasks = true;

  freezeSharedVariables();
  debianRepo.freeze();
  debianControlData.freeze();
  gpgFingerprint.freeze();
  gpgPassphrase.freeze();
  gpgPrivateKey.freeze();

  addTask(GrinderTask('pkg-debian-update',
      taskFunction: () => _update(),
      description: 'Update the Debian package.',
      depends: ['pkg-standalone-linux-x64']));
}

/// Releases the source code in a Debian package and
/// updates the PPA repository with the new package.
Future<void> _update() async {
  ensureBuild();

  final String packageName = standaloneName.value + "_" + version.toString();
  var repo =
      await cloneOrPull(url("https://github.com/$debianRepo.git").toString());

  if (gpgPrivateKey.value != null) {
    _importGpgPrivateKey();
  } else {
    log("pkg.gpgPrivateKey not set. Assuming GPG key is already imported.");
  }

  await _createDebianPackage(repo, packageName);
  await _releaseNewPackage(repo);
  await _gitUpdateAndPush(repo);

  if (gpgPrivateKey.value != null) _deleteGPGKey();
}

/// Creates a Debian package from the source code.
Future<void> _createDebianPackage(String repo, String packageName) async {
  var debianDir = await _createPackageDirectory(repo, packageName);

  _generateControlFile(debianDir);
  _copyExecutableFiles(debianDir);
  // Pack the files into a .deb file
  run("dpkg-deb", arguments: ["--build", packageName], workingDirectory: repo);
  delete(Directory(debianDir));
}

/// Scans the PPA [repo] for new packages and updates the
/// release files, also signing them.
Future<void> _releaseNewPackage(String repo) async {
  await _updatePackagesFile(repo);
  await _updateReleaseFile(repo);
  await _updateReleaseGPGFile(repo);
  await _updateInReleaseFile(repo);
}

/// Create the directory `repo/packageName` and relevant subfolders for the
/// debian package.
///
/// Returns the path of created folder.
Future<String> _createPackageDirectory(String repo, String packageName) async {
  var debianDir = p.join(repo, packageName);
  await Directory('$debianDir/DEBIAN').create(recursive: true);
  await Directory('$debianDir/usr/local/bin').create(recursive: true);
  return debianDir;
}

/// Copy all executable files listed in the map [executables] from the `build` folder
void _copyExecutableFiles(String debianDir) {
  var executablePath = p.join(debianDir, "usr", "local", "bin");
  for (var name in executables.value.keys) {
    safeCopy(p.join("build", "$name.native"), p.join(executablePath, name));
  }
}

/// Generate the control file for the Debian package.
void _generateControlFile(String debianDir) {
  var controlFilePath = p.join(debianDir, "DEBIAN", "control");

  var _updatedControlData = replaceFirstMappedMandatory(
      debianControlData.value,
      RegExp(r'Version: ([0-9].*)'),
      (match) => 'Version: ${version.toString()}',
      "Couldn't find a version field in the given CONTROL file.");

  writeString(controlFilePath, _updatedControlData);
}

/// Scan for new .deb packages in the [repo] and update the `Packages` file.
Future<void> _updatePackagesFile(String repo) async {
  // Scan for new packages
  var output = run("dpkg-scanpackages",
      arguments: ["--multiversion", "."], workingDirectory: repo);
  // Write the stdout to the file
  writeString(p.join(repo, 'Packages'), output);
  // Force Compress the Packages file
  log('Creating Packages.gz');
  var compressedBytes = GZipEncoder().encode(utf8.encode(output));
  File(p.join(repo, 'Packages.gz'))
      .writeAsBytesSync(compressedBytes as List<int>);
}

/// Generate the Release index for the PPA.
Future<void> _updateReleaseFile(String repo) async {
  var output = run("apt-ftparchive",
      arguments: ["release", "."], workingDirectory: repo);
  writeString(p.join(repo, 'Release'), output);
}

/// Sign the Release file with the GPG key.
Future<void> _updateReleaseGPGFile(String repo) async {
  run("gpg",
      arguments: [
        ..._gpgArgs,
        "--default-key",
        gpgFingerprint.value,
        "--passphrase",
        gpgPassphrase.value,
        "--armor",
        "--detach-sign",
        "--sign",
        "--output",
        "Release.gpg",
        "Release",
      ],
      quiet: true,
      workingDirectory: repo);
}

/// Update the InRelease file with the new index and keys.
Future<void> _updateInReleaseFile(String repo) async {
  run("gpg",
      arguments: [
        ..._gpgArgs,
        "--default-key",
        gpgFingerprint.value,
        "--passphrase",
        gpgPassphrase.value,
        "--clearsign",
        "--output",
        "InRelease",
        "Release",
      ],
      quiet: true,
      workingDirectory: repo);
}

/// Import the private key into the GPG.
void _importGpgPrivateKey() {
  log("Importing the GPG Private Key");
  writeString("._privateKey", gpgPrivateKey.value as String);
  run(
    "gpg",
    arguments: [
      ..._gpgArgs,
      "--passphrase",
      gpgPassphrase.value,
      "--allow-secret-key-import",
      "--import",
      "._privateKey"
    ],
    quiet: true,
  );
  runAsync("rm", arguments: ["._privateKey"]);
}

/// Delete the GPG key from the public and secret keyrings.
String _deleteGPGKey() {
  log("Cleaning up the GPG Keys");
  return run(
    "gpg",
    arguments: [
      ..._gpgArgs,
      "--delete-secret-and-public-key",
      gpgFingerprint.value,
    ],
    quiet: true,
  );
}

/// Commit all the changes in the PPA repository and push to the remote upstream.
Future<void> _gitUpdateAndPush(String repo) async {
  run("git",
      arguments: ["add", "."],
      workingDirectory: repo,
      runOptions: botEnvironment);

  run("git",
      arguments: [
        "commit",
        "--all",
        "--message",
        "Update $humanName to $version"
      ],
      workingDirectory: repo,
      runOptions: botEnvironment);

  await runAsync("git",
      arguments: [
        "push",
        url("https://$githubUser:$githubPassword@github.com/$debianRepo.git")
            .toString(),
        "HEAD:${await originHead(repo)}"
      ],
      workingDirectory: repo);
}
