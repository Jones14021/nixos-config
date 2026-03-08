#!/usr/bin/env python3
import sys
import re
import argparse
from pathlib import Path


def preprocess_markdown(filepath: Path, output_path: Path = None):
    """
    Scans a markdown file for missing blank lines before lists,
    asks the user to fix them, and writes the result to a new file.
    Outputs the path of the final file to stdout.
    """
    if not filepath.exists() or not filepath.is_file():
        print(f"Error: File '{filepath}' not found.", file=sys.stderr)
        sys.exit(1)

    # If no output path is provided, create a suffix like input_fixed.md
    if output_path is None:
        output_path = filepath.with_name(f"{filepath.stem}_fixed{filepath.suffix}")

    # Read the entire file content using pathlib
    lines = filepath.read_text(encoding="utf-8").splitlines()

    new_lines = []
    in_code_block = False

    # Matches common list markers (-, *, +) and numbered lists (1., 2., etc.)
    list_regex = re.compile(r"^\s*([-*+]|\d+\.)\s+")
    fixes_count = 0

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Track whether we are inside a code block (we don't want to modify contents there)
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_code_block = not in_code_block

        # If we encounter a list item and are NOT in a code block
        if not in_code_block and list_regex.match(line):
            if i > 0:
                prev = lines[i - 1]
                prev_is_blank = prev.strip() == ""
                prev_is_list_item = bool(list_regex.match(prev))
                # If the previous line is indented, it's likely a multi-line list item
                prev_is_indented = prev.startswith((" ", "\t"))

                # If preceded directly by text (no blank line, no other list item, not indented)
                if not prev_is_blank and not prev_is_list_item and not prev_is_indented:
                    new_lines.append("")  # Insert the missing blank line
                    fixes_count += 1

        new_lines.append(line)

    # Interactive prompt (only once for all discovered issues)
    # Note: We print to stderr so we don't mess up the stdout path return
    if fixes_count > 0:
        print(
            f"\n⚠️  Found {fixes_count} missing blank line(s) before lists in '{filepath}'.",
            file=sys.stderr,
        )

        # Ensure input prompt is also routed correctly, reading directly from stdin/stderr context
        print(
            "Do you want to automatically fix these issues and write to a new file? (Y/n): ",
            end="",
            file=sys.stderr,
        )
        sys.stderr.flush()
        ans = input().strip().lower()

        if ans in ["", "y", "yes"]:
            # Write the fixed content to the new output path
            output_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
            print(f"✅ Fixed file written to: {output_path}\n", file=sys.stderr)
            # Output ONLY the path to stdout for bash piping
            print(output_path)
            return
        else:
            print(
                "❌ No changes made. Proceeding with original file.\n", file=sys.stderr
            )
            # Output the original path since user declined changes
            print(filepath)
            return
    else:
        print(
            f"✅ No missing blank lines found in '{filepath}'. All good!\n",
            file=sys.stderr,
        )
        # Output the original path since no changes were needed
        print(filepath)
        return


def main():
    parser = argparse.ArgumentParser(
        description="Fixes missing blank lines before lists in Markdown files for Pandoc compatibility."
    )

    parser.add_argument(
        "filepath", type=Path, help="Path to the input markdown file (e.g., input.md)"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Optional: Path for the fixed output file. Defaults to <input>_fixed.md",
    )

    args = parser.parse_args()
    preprocess_markdown(args.filepath, args.output)


if __name__ == "__main__":
    main()
