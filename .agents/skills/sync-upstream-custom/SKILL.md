---
name: sync-upstream-custom
description: Synchronize this forked infinite-canvas project with the upstream repository https://github.com/HuFakai/infinite-canvas while preserving local custom changes. Use this skill whenever the user asks to pull, fetch, merge, sync, update, or integrate upstream/remote changes for this project, especially when they mention keeping local modifications such as start-pro.bat, start.bat, stop.bat, local docs, package edits, or other custom files. This skill should also trigger for Chinese requests like “拉取上游更新”, “同步远程代码”, “保留本地修改”, “融合远程更新和本地改动”, “fork 更新了帮我拉取”, or “有冲突先问我”.
---

# Sync Upstream While Preserving Local Customizations

This skill guides synchronization of this local fork with `https://github.com/HuFakai/infinite-canvas` while protecting local custom changes. The goal is to integrate upstream code updates and keep local custom behavior intact. If a conflict could change upstream functionality or local custom functionality, stop and ask the user for a decision with concrete options.

## Core Rules

- Do not discard, reset, checkout, or overwrite local changes unless the user explicitly asks for that exact destructive operation.
- Do not push to any remote unless the user explicitly asks.
- Prefer a clean, inspectable Git flow: check status, fetch upstream, compare histories, merge or rebase only when the state is understood.
- Treat local custom files as important even if they are not present upstream. In this project, examples include `start-pro.bat`, `start.bat`, `stop.bat`, local docs, environment helpers, and local package or startup changes.
- If conflicts are non-trivial or affect behavior, explain the tradeoff and ask before resolving.
- Keep user-facing replies in Chinese unless the user explicitly requests another language.

## Remote Assumptions

Use `upstream` when it points to `https://github.com/HuFakai/infinite-canvas`.

If `upstream` is missing but another remote points to that URL, use the existing matching remote and mention it.

If no remote points to `https://github.com/HuFakai/infinite-canvas`, add it as `upstream`:

```powershell
git remote add upstream https://github.com/HuFakai/infinite-canvas.git
```

Do not change `origin` unless the user explicitly requests it.

## Standard Workflow

1. Inspect current state before changing anything:

```powershell
git status --short --branch
git remote -v
git branch --show-current
git log --oneline --decorate -5
```

2. Identify local custom changes:

```powershell
git diff --name-status
git diff --cached --name-status
git ls-files --others --exclude-standard
```

Also compare committed local differences against upstream after fetch:

```powershell
git fetch upstream
git fetch upstream --tags
git log --oneline --left-right --cherry-pick HEAD...upstream/main
git diff --name-status upstream/main..HEAD
git diff --name-status HEAD..upstream/main
```

Also check whether upstream has a newer release tag than the version files:

```powershell
git tag --list "v*" --sort=-v:refname
git show upstream/main:VERSION
git show upstream/main:web/package.json | Select-String -Pattern '"version"'
```

If the newest upstream tag is newer than `VERSION`, `web/package.json`, or `web/package-lock.json`, align local version files to the newest upstream tag after confirming the tag belongs to the upstream history. This project follows upstream releases closely; local minor customizations should not leave the visible app version behind the latest upstream release tag.

3. If the working tree has uncommitted changes, protect them before integrating upstream:

- Prefer asking the user whether they want to commit local changes when the changes look intentional and broad.
- For small local edits where the user clearly asked to sync now, use a named stash:

```powershell
git stash push --include-untracked -m "before-upstream-sync"
```

Then reapply it after the upstream integration:

```powershell
git stash pop
```

If `git stash pop` creates conflicts, do not guess. Follow the conflict handling section.

4. Choose the integration strategy:

- If `upstream/main` is already an ancestor of `HEAD`, no merge is needed. Report that the project already includes upstream and local custom commits are preserved.
- If `HEAD` is an ancestor of `upstream/main`, fast-forward is acceptable only when there are no local-only commits that need to remain separate.
- If there are local custom commits and upstream has new commits, merge `upstream/main` into the current branch to preserve local history:

```powershell
git merge upstream/main
```

Avoid rebase by default because the user wants to preserve local custom modifications and may have local commits already pushed to their fork.

5. After merge or fast-forward, verify state:

```powershell
git status --short --branch
git log --oneline --decorate --graph --max-count=12 --all
```

Do not run builds or tests unless the user explicitly asks; this project rule says the user will run them.

## Conflict Handling

When Git reports conflicts, inspect them before editing:

```powershell
git status --short
git diff --name-only --diff-filter=U
git diff --check
```

For each conflicted file, classify the conflict.

### Safe To Resolve Directly

Resolve directly only when the conflict is mechanical and does not change behavior, such as:

- Import ordering or formatting where both sides keep the same symbols.
- Adjacent documentation edits where both meanings can be retained.
- Local helper scripts that upstream does not use and can be kept as-is.
- Lockfile conflict only after checking the corresponding package manifest and preserving real dependency changes from both sides.

### Ask The User Before Resolving

Pause and ask when conflict resolution could affect either upstream functionality or local custom functionality:

- Code in `web/src/`, `handler/`, `service/`, `repository/`, `model/`, or other runtime paths where both sides changed behavior.
- Startup scripts such as `start-pro.bat`, `start.bat`, `stop.bat` if upstream also introduced or changed scripts with overlapping responsibilities.
- Config files, package manifests, lockfiles, Docker files, API settings, theme files, or environment assumptions that may change how the app runs.
- Deletions from upstream that conflict with local additions or modifications.
- Any conflict where the correct result depends on product intent rather than syntax.

When asking, include:

- The conflicted file path.
- What upstream changed.
- What local customization changed.
- Why the conflict matters.
- Two or three concrete options, with the least risky option first.

Use concise Chinese. Example:

```text
`web/package-lock.json` 有冲突。上游更新了依赖版本，本地也改过锁文件；直接保留一边可能导致依赖和 `package.json` 不一致。

建议：
1. 以 `package.json` 为准重新生成 lockfile，保留两边真实依赖变更。
2. 优先采用上游 lockfile，再手动补回本地依赖。
3. 暂停合并，先让我列出具体依赖差异。

你希望按哪种处理？
```

## Resolution Principles

- Preserve upstream feature changes unless they directly conflict with a local customization the user wants.
- Preserve local custom changes unless they block upstream behavior or introduce obvious breakage.
- When both sides are valid, prefer composing them instead of choosing one side.
- Do not hide unresolved uncertainty with silent fallbacks.
- Leave conflicts unresolved and ask when there is not enough context.

## Final Report

After the sync is complete, report:

- Which remote and branch were fetched.
- Whether a merge, fast-forward, or no-op happened.
- Which local custom changes were preserved.
- Whether conflicts occurred and how they were resolved.
- Current `git status --short --branch`.

Keep the final answer short and factual.
