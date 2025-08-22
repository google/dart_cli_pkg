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

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:cli_pkg/src/last_changelog_section.dart';

void main() {
  void assertReleaseNotesFromChangelog(String changelog, Object matcher) {
    expect(lastChangelogSection(changelog, Version.parse('1.2.3')), matcher);
  }

  test("only includes the first entry", () {
    assertReleaseNotesFromChangelog(
      "## 1.2.3\n"
      "This is a great release!\n"
      "## 1.2.3\n"
      "This one... not so great.",
      allOf([
        contains("This is a great release!"),
        isNot(contains("This one... not so great")),
      ]),
    );
  });

  group("consolidates multi-line paragraphs", () {
    test("at the top level", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "This is a\n"
        "great release!\n",
        startsWith("This is a great release!"),
      );
    });

    test("in a list", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "* This is a\n"
        "  great release!\n",
        startsWith("* This is a great release!"),
      );
    });
  });

  group("leaves separate paragraphs separate", () {
    test("at the top level", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "This is a great release!\n\n"
        "Give it a try!",
        startsWith(
          "This is a great release!\n\n"
          "Give it a try!",
        ),
      );
    });

    test("in a list", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "* This is a great release!\n\n"
        "  Give it a try!",
        startsWith(
          "* This is a great release!\n\n"
          "  Give it a try!",
        ),
      );
    });
  });

  group("leaves code blocks as-is", () {
    test("at the top level", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "```scss\n"
        "a {\n"
        "  b: c;\n"
        "\n"
        "  d: e;\n"
        "}\n"
        "```",
        startsWith(
          "```scss\n"
          "a {\n"
          "  b: c;\n"
          "\n"
          "  d: e;\n"
          "}\n"
          "```",
        ),
      );
    });

    test("in a list", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "* ```scss\n"
        "  a {\n"
        "    b: c;\n"
        "\n"
        "    d: e;\n"
        "  }\n"
        "  ```",
        startsWith(
          "* ```scss\n"
          "  a {\n"
          "    b: c;\n"
          "\n"
          "    d: e;\n"
          "  }\n"
          "  ```",
        ),
      );
    });
  });

  group("leaves groups of link reference definitions as-is", () {
    test("at the top level", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "[a], [b], [c]\n"
        "\n"
        "[a]: http://a.com\n"
        "[b]: http://b.org\n"
        "[c]: http://c.net\n",
        startsWith(
          "[a], [b], [c]\n"
          "\n"
          "[a]: http://a.com\n"
          "[b]: http://b.org\n"
          "[c]: http://c.net",
        ),
      );
    });

    test("in a list", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "* [a], [b], [c]\n"
        "\n"
        "  [a]: http://a.com\n"
        "  [b]: http://b.org\n"
        "  [c]: http://c.net\n",
        startsWith(
          "* [a], [b], [c]\n"
          "\n"
          "  [a]: http://a.com\n"
          "  [b]: http://b.org\n"
          "  [c]: http://c.net",
        ),
      );
    });
  });

  group("leaves lists as-is", () {
    test("with *", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "Before\n"
        "* One\n"
        "* Two\n"
        "* Three\n"
        "After\n",
        startsWith(
          "Before\n"
          "* One\n"
          "* Two\n"
          "* Three\n"
          "After",
        ),
      );
    });

    test("with -", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "Before\n"
        "- One\n"
        "- Two\n"
        "- Three\n"
        "After\n",
        startsWith(
          "Before\n"
          "- One\n"
          "- Two\n"
          "- Three\n"
          "After",
        ),
      );
    });

    test("with 1.", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "Before\n"
        "1. One\n"
        "2. Two\n"
        "3. Three\n"
        "After\n",
        startsWith(
          "Before\n"
          "1. One\n"
          "2. Two\n"
          "3. Three\n"
          "After",
        ),
      );
    });

    test("with 1)", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "Before\n"
        "1) One\n"
        "2) Two\n"
        "3) Three\n"
        "After\n",
        startsWith(
          "Before\n"
          "1) One\n"
          "2) Two\n"
          "3) Three\n"
          "After",
        ),
      );
    });

    test("in a list", () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "* * One\n"
        "  * Two\n"
        "  * Three\n",
        startsWith(
          "* * One\n"
          "  * Two\n"
          "  * Three",
        ),
      );
    });
  });

  test(
    "folds a line that looks like a link reference definition in a paragraph",
    () {
      assertReleaseNotesFromChangelog(
        "## 1.2.3\n"
        "\n"
        "[a]\n"
        "[a]: http://a.com\n",
        startsWith("[a] [a]: http://a.com"),
      );
    },
  );
}
