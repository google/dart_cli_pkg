// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';

import 'utils.dart';

/// The release channels for the Dart SDK.
enum SdkChannel {
  stable,
  beta,
  dev;

  /// Whether this is a stable SDK release.
  bool get isStable => this == stable;

  /// Whether this is a beta SDK release.
  bool get isBeta => this == beta;

  /// Whether this is a dev SDK release.
  bool get isDev => this == dev;

  static final SdkChannel current = switch (dartVersion) {
    Version(isPreRelease: false) => stable,
    Version(preRelease: ["beta", ...]) => beta,
    Version(preRelease: ["dev", ...]) => dev,
    _ => fail("Unrecognized Dart SDK version $dartVersion")
  };

  String toString() => name;
}
