/// 构建时可选：`--dart-define=UPDATE_GITHUB_REPO=owner/repo`（与 GitHub Releases 对应）。
const String kUpdateGithubRepoFromDefine =
    String.fromEnvironment('UPDATE_GITHUB_REPO', defaultValue: '');

/// 若未使用 dart-define，可在发布前填写此处（与上方二选一），例如 `yourname/quickbox`。
const String kUpdateGithubRepoFallback = '';
