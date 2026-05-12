# Repository Guidelines

## Project Structure & Module Organization

This repository is a single Noctalia plugin. Keep runtime logic in [Main.qml](./Main.qml), bar UI in [BarWidget.qml](./BarWidget.qml), Control Center UI in [ControlCenterWidget.qml](./ControlCenterWidget.qml), and plugin settings UI in [Settings.qml](./Settings.qml). Plugin metadata lives in [manifest.json](./manifest.json), and user-facing behavior notes belong in [README.md](./README.md).

Add new files only when the feature has a clear boundary. Prefer keeping small UI behaviors in the relevant widget file rather than splitting prematurely.

## Build, Test, and Development Commands

- `git status`: inspect local changes inside the plugin repo.
- `qmllint BarWidget.qml Main.qml ControlCenterWidget.qml Settings.qml`: basic QML validation when local imports are configured.
- `qs kill -c noctalia-shell && qs -c noctalia-shell -d`: restart Noctalia Shell to reload the plugin after edits.
- `niri msg --json outputs`: inspect current output names and transforms while debugging rotation behavior.

Runtime reload in Noctalia is the primary validation path for this repository.

## Coding Style & Naming Conventions

Use 4-space indentation in QML and JSON. Follow existing QML naming: `camelCase` for properties and functions, `PascalCase` for QML types, and descriptive filenames such as `BarWidget.qml`. Keep comments sparse and only where behavior is not obvious.

Do not introduce unnecessary abstractions. This plugin is small; optimize for readability over reuse.

## Testing Guidelines

There is no automated test suite yet. Validate changes by:

- reloading Noctalia Shell,
- confirming the plugin appears in the plugin manager and bar widget list,
- testing the bar widget, Control Center widget, and settings UI manually,
- checking for QML load errors in Quickshell logs.

When fixing bugs, reproduce the issue first and note the manual verification steps in your change notes.

## Commit & Pull Request Guidelines

This repository has no established Git history yet. Use short, imperative commit messages such as `Add plugin settings menu` or `Fix BarWidget import`. Keep each commit focused on one change.

For pull requests, include a short summary, manual test steps, and screenshots for visible UI changes. Mention any Noctalia or Niri assumptions that reviewers need to reproduce the behavior.
