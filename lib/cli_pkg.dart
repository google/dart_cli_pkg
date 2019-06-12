// Copyright 2019 Google LLC
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

import 'standalone.dart' as standalone;

export 'src/info.dart';

// Manually export tasks to work around google/grinder.dart#337

@Task('Build Dart script snapshot(s).')
void pkgCompileSnapshot() => standalone.pkgCompileSnapshot();

@Task('Build Dart native executable(s).')
void pkgCompileNative() => standalone.pkgCompileNative();

@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Linux.')
Future<void> pkgStandaloneLinuxIa32() => standalone.pkgStandaloneLinuxIa32();

@Task('Build a standalone 64-bit package for Linux.')
Future<void> pkgStandaloneLinuxX64() => standalone.pkgStandaloneLinuxX64();

@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Mac OS.')
Future<void> pkgStandaloneMacOsIa32() => standalone.pkgStandaloneMacOsIa32();

@Task('Build a standalone 64-bit package for Mac OS.')
Future<void> pkgStandaloneMacOsX64() => standalone.pkgStandaloneMacOsX64();

@Depends(pkgCompileSnapshot)
@Task('Build a standalone 32-bit package for Windows.')
Future<void> pkgStandaloneWindowsIa32() =>
    standalone.pkgStandaloneWindowsIa32();

@Task('Build a standalone 64-bit package for Windows.')
Future<void> pkgStandaloneWindowsX64() => standalone.pkgStandaloneWindowsX64();

@Task('Build all standalone packages.')
Future<void> pkgStandaloneAll() => standalone.pkgStandaloneAll();
