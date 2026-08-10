# Fix and PR Workflow

Runs ScriptAnalyzer, fixes all issues, runs Pester tests, commits to a feature branch, creates a PR, merges it, and cleans up the branch.

## Steps

1. **Lint**: Run `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error` to identify all lint issues
2. **Fix**: For each warning or error found, fix it, then re-run the analyzer on that file to confirm the fix before moving to the next
3. **Test**: Run `Invoke-Pester` to ensure all tests pass
   - If any tests fail, diagnose and fix the root cause, then re-run tests
   - Repeat until all tests pass with zero failures
4. **Re-lint**: Run `Invoke-ScriptAnalyzer` again to confirm zero warnings remain after test fixes
5. **Branch**: Create a feature branch: `git checkout -b fix/<brief-description>`
6. **Commit**: Stage all changed files and commit with a descriptive message summarizing every fix
7. **Push & PR**: Push the branch and create a PR with a markdown body listing each file changed and what was fixed
8. **Merge & Cleanup**:
   - Merge the PR
   - Switch to main first: `git checkout main`
   - Then delete the feature branch: `git branch -d fix/<brief-description>`

## Rules

- Always switch to main before deleting feature branches
- Perform file writes sequentially, not in parallel, to avoid cascade failures
- Never commit if ScriptAnalyzer warnings or test failures remain
- Use `Write-ToLog` (not `Write-Log`) as the standard logging function
- All fixes must be cross-platform compatible (macOS and Windows)
