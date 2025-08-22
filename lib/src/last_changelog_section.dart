// Copyright 2022 Google LLC
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

import 'package:charcode/charcode.dart';
import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:string_scanner/string_scanner.dart';

/// A regular expression that matches a Markdown code block.
final _codeBlock = RegExp(" *```");

/// A regular expression that matches a Markdown link reference definition..
final _linkReferenceDefinition = RegExp(r" *\[([^\]\\]|\\[\]\\])+\]:");

/// A regular expression that matches a Markdown list item.
final _listItem = RegExp(r" *([*-]|\d+[.)]) ");

/// Extracts the first CHANGELOG entry from [text], reformatted to remove line
/// breaks that will show up in GitHub release notes.
///
/// The [version] is the version we expect to appear at the top of the
/// changelog.
String lastChangelogSection(
  String text,
  Version version, {
  Object? sourceUrl,
}) => _Extractor(text, sourceUrl: sourceUrl).extract(version);

/// A class that extracts the first entry from a changelog, reformatted to
/// remove line breaks that will show up in GitHub release notes.
class _Extractor {
  /// The scanner that scans the changelog.
  final StringScanner _scanner;

  /// The buffer to which to write the extracted entry.
  final _buffer = StringBuffer();

  /// Whether we're currently consuming a paragraph of text.
  var _inParagraph = false;

  /// A stack of expected indentation level for the current block(s).
  ///
  /// This is only added to when parsing a list item. Later elements represent
  /// more deeply-nested blocks.
  final _indentationLevels = <int>[];

  _Extractor(String text, {Object? sourceUrl})
    : _scanner = StringScanner(text, sourceUrl: sourceUrl);

  String extract(Version version) {
    if (!_scanner.scan(
      RegExp("## ${RegExp.escape(version.toString())}\r?\n"),
    )) {
      fail(
        "Failed to extract GitHub release notes from CHANGELOG.md.\n"
        'Expected it to start with "## $version".\n'
        "Set pkg.githubReleaseNotes to explicitly declare release notes.",
      );
    }

    while (!_scanner.isDone && !_scanner.matches("## ")) {
      if (!_tryIndentation()) {
        if (_inParagraph) _buffer.writeln();
        _inParagraph = false;
        _indentationLevels.removeLast();
      } else {
        _scanAfterIndentation(false);
      }
    }

    return _buffer.toString().trim();
  }

  /// Scans a line after consuming either the appropriate amount of indentation
  /// or the beginning of a Markdown list.
  ///
  /// The [afterListItem] argument indicates whether [_scanner] is currently on
  /// the same line as a list item.
  void _scanAfterIndentation(bool afterListItem) {
    if (_scanner.matches(_codeBlock)) {
      if (_inParagraph) _buffer.writeln();
      _inParagraph = false;

      do {
        if (!afterListItem && _scanner.peekChar() != $lf) _writeIndentation();
        afterListItem = false;
        _scanLine();
        _buffer.writeln();
        if (!_tryIndentation()) {
          _scanner.error(
            "Expected ${_indentationLevels.last} spaces of indentation.",
          );
        }
      } while (!_scanner.matches(_codeBlock));

      _writeIndentation();
      _scanLine();
      _buffer.writeln();
    } else if (_scanner.scan(_listItem)) {
      if (_inParagraph) _buffer.writeln();
      _inParagraph = false;

      if (!afterListItem) _writeIndentation();
      _buffer.write(_scanner.lastMatch![0]);
      _indentationLevels.add(_scanner.lastMatch![0]!.length);
      _scanAfterIndentation(true);
    } else if (!_inParagraph && _scanner.matches(_linkReferenceDefinition)) {
      if (!afterListItem) _writeIndentation();
      _scanLine();
      _buffer.writeln();
    } else if (_scanner.matches(RegExp(" *\n"))) {
      if (_inParagraph) _buffer.writeln();
      _inParagraph = false;

      _scanLine();
      _buffer.writeln();
    } else {
      if (_inParagraph) {
        _buffer.writeCharCode($space);
      } else if (!afterListItem) {
        _writeIndentation();
      }
      _scanLine();
      _inParagraph = true;
    }
  }

  /// Consumes the current indentation level if the current line matches it, or
  /// returns `false` if it doesn't.
  bool _tryIndentation() {
    if (_indentationLevels.isEmpty) return true;

    var level = _indentationLevels.last;
    for (var i = 0; i < level; i++) {
      if (_scanner.scanChar($space)) continue;
      if (_scanner.scanChar($tab)) {
        // Tabs count as four spaces of indentation in Markdown.
        i += 3;
        continue;
      }

      // Whitespace-only lines always count as fully indented.
      return _scanner.peekChar() == $lf;
    }
    return true;
  }

  /// Writes spaces equal to the current indentation level.
  void _writeIndentation() {
    if (_indentationLevels.isEmpty) return;
    _buffer.write(" " * _indentationLevels.last);
  }

  /// Scans the remainder of the current line and writes it to [_buffer].
  ///
  /// This consumes the trailing newline but doesn't write it.
  void _scanLine() {
    var start = _scanner.position;
    while (!_scanner.isDone && _scanner.peekChar() != $lf) {
      _scanner.readChar();
    }
    _buffer.write(_scanner.substring(start));
    _scanner.scanChar($lf);
  }
}
