<div align="center">

<img src="assets/qb.png" width="100" alt="Quick Box logo" />

# Quick Box

**A lightweight frosted-glass desktop launcher and stash — built with Flutter**

[简体中文](README.zh-CN.md)

</div>

---

## Overview

**Quick Box** is a lightweight **Windows** desktop utility: invoke a frosted-glass popup via global hotkeys, search across **Quick Apps, Web Shortcuts, Commands, and Notes** in one place, with pinyin-aware fuzzy ranking, and optional **S3-compatible cloud sync** for web/command/note data (Quick Apps user list stays local).

## Screenshots

<p align="center">
  <b>Main window</b><br />
  <img src="docs/example1.png" alt="Quick Box main window" width="780" />
</p>

<p align="center">
  <b>Global search</b> (results across all cards, with card-type badges)<br />
  <img src="docs/example2.png" alt="Quick Box search results" width="780" />
</p>

<p align="center">
  <b>New quick note</b> (structured note form)<br />
  <img src="docs/example3.png" alt="Quick Box create note" width="780" />
</p>

## Highlights

| Capability | Description |
|------------|-------------|
| **Global hotkeys** | Show/hide, center window, per-card shortcuts |
| **Hybrid search** | Chinese, pinyin, fuzzy matching and ranking |
| **Four cards** | App index, web (favicon, etc.), shell commands, structured notes |
| **Frosted UI** | Blurred, rounded window suited for overlay use |
| **System tray** | Background stay; open settings or exit from tray |
| **Data root** | Configurable folder for index + `user_entries.json` |
| **Cloud sync** | S3-compatible storage; pull on startup, debounced push on change, manual download in Settings |

## Requirements

- Windows 10 / 11 (x64)
- [Flutter](https://flutter.dev/) stable channel (**Dart ^3.11** per `pubspec.yaml`)

## Run

```bash
flutter pub get
flutter run -d windows
```

Release build:

```bash
flutter build windows
```

## Cloud sync

- Configure **Settings → Cloud Sync** (endpoint, bucket, keys) and **enable** the toggle.
- Synced scope: **web shortcuts, commands, notes** only — **not** the Quick Apps user list.
- Credentials are stored locally (e.g. SharedPreferences); protect your machine and IAM policies.

## Repository layout (excerpt)

```
lib/
  main.dart
  pages/
  cards/
  services/
assets/
  qb.png / qb.ico
docs/
  example1.png
  example2.png
  example3.png
```

---

<div align="center">

**Quick Box** — Keep your shortcuts one keystroke away.

</div>
