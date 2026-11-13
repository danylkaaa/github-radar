PR Status shows your GitHub pull requests in the macOS menu bar.

## Features

- Menu bar counts: to review / yours / ready to merge, with a dot for the most urgent news.
- Cards with size, latest commit, CI, reviews, comments and participants.
- Hover for details: CI checks, reviewers, comments, commits. Every item links to GitHub.
- Activity of the last 7 days, and insights on when and where you work.
- Your own layout, and keyboard control (⌥⌘P opens the dropdown).

## Install

1. Download `PRStatus-macos-arm64.zip` below.
2. Unzip it and move `PRStatus.app` to `/Applications`.
3. The app is not notarized by Apple, so macOS blocks it at first. Remove the download mark once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/PRStatus.app
   ```

4. Open PR Status. The icon appears in the menu bar.

## Requirements

macOS 14 or later, Apple silicon.

## Verify the download

Put both files in one folder and run `shasum -a 256 -c PRStatus-macos-arm64.zip.sha256`.
