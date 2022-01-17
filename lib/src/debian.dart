import 'dart:io';

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
/// It's modifiable.
///
/// `cli_pkg` will automatically update the `version` field when building the package.
final controlData = InternalConfigVariable.fn<String>(() =>
    File("control").existsSync()
        ? File("control").readAsStringSync()
        : fail("pkg.controlData must be set to update Debian package."));

/// The fingerprint for GPG key to use when signing the release.
///
/// By default, this comes from the `GPG_FINGERPRINT` environment variable.
final gpgFingerprint = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GPG_FINGERPRINT"] ??
    fail("pkg.gpgPassphrase must be set to deploy to PPA repository."));

/// The passphrase for the GPG key to use when signing the release.
///
/// By default, this comes from the `GPG_PASSPHRASE` environment variable.
final gpgPassphrase = InternalConfigVariable.fn<String>(() =>
    Platform.environment["GPG_PASSPHRASE"] ??
    fail("pkg.gpgPassphrase must be set to deploy to PPA repository."));

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
  controlData.freeze();
  gpgFingerprint.freeze();
  gpgPassphrase.freeze();

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

  await _createDebianPackage(repo, packageName);
  // TODO: Functions to Release and Upload the package to Git Upstream
}

/// Creates a Debian package from the source code.
Future<void> _createDebianPackage(String repo, String packageName) async {
  String debianDir = await _createPackageDirectory(repo, packageName);

  _generateControlFile(debianDir);
  _copyExecutableFiles(debianDir);
  // Pack the files into a .deb file
  run("dpkg-deb", arguments: ["--build", packageName], workingDirectory: repo);
  await _removeDirectory(debianDir);
}

/// Delete the Directory with path [directory].
Future<void> _removeDirectory(String directory) async {
  var result = await Process.run("rm", ["-r", directory]);
  if (result.exitCode != 0) {
    fail('Unable to remove the directory\n${result.stderr}');
  }
}

/// Create the directory `repo/packageName` and relevant subfolders for the
/// debian package.
///
/// Returns the path of created folder.
Future<String> _createPackageDirectory(String repo, String packageName) async {
  String debianDir = p.join(repo, packageName);
  await Directory('$debianDir/DEBIAN').create(recursive: true);
  await Directory('$debianDir/usr/local/bin').create(recursive: true);
  return debianDir;
}

/// Copy all executable files listed in the map [executables] from the `build` folder
void _copyExecutableFiles(String debianDir) {
  final executablePath = p.join(debianDir, "usr", "local", "bin");
  executables.value.forEach((name, path) {
    run("cp", arguments: [
      p.join("build", "$name.native"),
      p.join(executablePath, name)
    ]);
  });
}

/// Generate the control file for the Debian package.
void _generateControlFile(String debianDir) {
  var controlFilePath = p.join(debianDir, "DEBIAN", "control");

  String _updatedControlData = replaceFirstMappedMandatory(
      controlData.value,
      RegExp(r'Version: ([0-9].*)'),
      (match) => 'Version: ${version.toString()}',
      "Couldn't find a version field in the given CONTROL file.");

  writeString(controlFilePath, _updatedControlData);
}
