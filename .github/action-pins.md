# GitHub Action pins

Every external action in `.github/workflows/*.yml` is pinned to a full
40-character commit SHA, with the exact release in a trailing `# vX.Y.Z`
comment. Tags are mutable; SHAs are not. Majors are not upgraded by a
pin refresh (both actions stay on v4).

| Action | Release | Commit SHA | Upstream release |
|---|---|---|---|
| `actions/checkout` | v4.4.0 | `11d5960a326750d5838078e36cf38b85af677262` | https://github.com/actions/checkout/releases/tag/v4.4.0 |
| `actions/upload-artifact` | v4.6.2 | `ea165f8d65b6e75b540449e92b4886f43607fa02` | https://github.com/actions/upload-artifact/releases/tag/v4.6.2 |

Both tags are lightweight (the ref points straight at a commit).

## Bump procedure

1. Pick the target release on the upstream releases page (same major unless
   a major bump is separately approved). Read the release notes and diff
   against the current SHA: `gh api repos/OWNER/REPO/compare/OLDSHA...NEWSHA`.
2. Resolve the tag to a commit:
   ```
   gh api repos/OWNER/REPO/git/ref/tags/vX.Y.Z -q '.object.type+" "+.object.sha'
   ```
   If the type is `tag` (annotated), dereference it:
   `gh api repos/OWNER/REPO/git/tags/<sha> -q '.object.sha'`. Use the
   resulting commit SHA, never the tag-object SHA.
3. Verify the commit exists: `gh api repos/OWNER/REPO/commits/<sha> -q .sha`.
4. Replace the SHA and the `# vX.Y.Z` comment in every workflow
   (`grep -rn 'uses:' .github/workflows`) and update the table above.
5. Confirm every `uses:` is `owner/repo@<40 hex>` and CI passes.
