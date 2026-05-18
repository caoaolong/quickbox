/// 构建时可选：`--dart-define=UPDATE_GITHUB_REPO=owner/repo`（与 GitHub Releases 对应）。
const String kUpdateGithubRepoFromDefine =
    String.fromEnvironment('UPDATE_GITHUB_REPO', defaultValue: '');

/// 若未使用 dart-define、也未写 `.env`，则使用此处回退值（便于本地调试）。
/// Fork 改成自己的仓库，或用 `UPDATE_GITHUB_REPO` / `--dart-define` 覆盖。
const String kUpdateGithubRepoFallback = 'caoaolong/quickbox';
