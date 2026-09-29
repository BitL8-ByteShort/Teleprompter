# Repository access

Checked September 29, 2026: `BitL8-ByteShort/Teleprompter` is private. Its owner,
`BitL8-ByteShort`, is the only collaborator. There are no pending collaborator
invitations or deploy keys. GitHub Actions has read-only default permissions and
cannot approve pull requests.

Other people currently have no permission to alter this repository. Contributions
are welcome, but outside write access should wait until the branch rules below
are active.

## When the repository becomes public

Public visibility lets people read and fork the code; it does not give them
permission to change our repository. Keep the owner as the only person with write
access. Contributors can work in their own forks and submit pull requests for
the owner to review and merge. See
[GitHub's access documentation](https://docs.github.com/en/repositories/creating-and-managing-repositories/access-to-repositories).

GitHub Free supports protection for public repositories, so no Pro subscription
is needed for that release. Once publication is authorized and the repository
becomes public, run the command below and verify active protection before
granting any additional write access. The prepared setup works for both public
and private repositories; it does not publish the repository itself.

## Main branch rules

**Branch protection is not enabled.** GitHub rejected ruleset access with
HTTP 403: "Upgrade to GitHub Pro or make this repository public to enable this
feature." The repository remains private. GitHub documents this
[plan requirement](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).

The prepared ruleset in `.github/main-ruleset.json` requires contributors to:

- Open a pull request instead of changing `main` directly.
- Obtain the owner's approval, with fresh approval after further changes.
- Resolve review conversations before merging.
- Avoid force pushes and deletion of `main`.

The owner retains an explicit bypass. `.github/CODEOWNERS` names the owner as
reviewer for every file; that file alone does not block pushes or merges.

When the repository is public, or has a plan supporting private rulesets,
activate and verify the saved rules:

```sh
python3 script/protect_main.py
```

The script creates or updates only the named ruleset and reads it back to verify
enforcement. It never changes visibility, adds collaborators, or upgrades a
GitHub plan. Grant outside write access only after it confirms active protection.
The contributor agreement still needs the manual checks in
[CONTRIBUTING.md](../CONTRIBUTING.md).
