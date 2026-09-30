# Repository access

Checked September 29, 2026: `BitL8-ByteShort/Teleprompter` is public. Its owner,
`BitL8-ByteShort`, is the only collaborator with write access. There are no pending
collaborator invitations or deploy keys. GitHub Actions has read-only default
permissions and cannot approve pull requests.

Other people can read the code and propose contributions, but have no permission
to alter this repository directly.

## Public contributions

Public visibility lets people read and fork the code; it does not give them
permission to change our repository. Keep the owner as the only person with write
access. Contributors can work in their own forks and submit pull requests for
the owner to review and merge. See
[GitHub's access documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/access-to-repositories).

GitHub Free supports protection for public repositories, so no Pro subscription
is needed. Public visibility does not change the proprietary license or remove
the contributor agreement's separate acceptance requirement.

## Main branch rules

**Main branch protection is active.** GitHub's
[Protect main ruleset](https://github.com/BitL8-ByteShort/Teleprompter/rules/24219843)
was enabled and read back after public launch. Its target is `refs/heads/main`.
The stored configuration is `.github/main-ruleset.json`.

The active rules require contributors to:

- Open a pull request instead of changing `main` directly.
- Obtain the owner's approval, with fresh approval after further changes.
- Resolve review conversations before merging.
- Avoid force pushes and deletion of `main`.

The owner retains an explicit bypass. `.github/CODEOWNERS` names the owner as
reviewer for every file; that file alone does not block pushes or merges.

To reapply and verify the saved rules:

```sh
python3 script/protect_main.py
```

The script creates or updates only the named ruleset and reads it back to verify
enforcement. It never changes visibility, adds collaborators, or upgrades a
GitHub plan. Preserve owner-only write access for ordinary fork contributions.
The contributor agreement still needs the manual checks in
[CONTRIBUTING.md](../CONTRIBUTING.md).
