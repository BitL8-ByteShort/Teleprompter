# Contributing to Teleprompter

Bug reports, fixes, documentation improvements, and focused feature contributions
are welcome. Teleprompter is currently a private project, so source contributions
require repository access. Access is managed by the maintainers.

The app uses a [proprietary license](LICENSE). Accepting contributions doesn't
make the whole project open source. The [contributor agreement](CLA.md) lets
you keep ownership of your work while giving Salty Panda LLC permission to
include it in future releases, including releases with different licensing terms.

## Before writing code

For a substantial change, open an issue in this repository first. Explain the
problem and the behavior you want. A small bug fix or documentation correction
can go straight into a pull request.

Keep the app focused on reading scripts near the camera. Preserve local script
storage, local speech recognition, optional model downloads, and the existing
playback controls unless the issue specifically calls for a change.

## Submit a change

1. Create a branch from `main` in your authorized checkout.
2. Make one focused change. Include a regression test when it proves a meaningful
   behavior, especially for playback, speech alignment, or saved scripts.
3. Run the checks relevant to your change. Describe what you actually tested
   and anything you couldn't verify on your Mac.
4. Open a pull request using the template. Explain the problem, the resulting
   behavior, and any new dependencies or third-party material.
5. Read [CLA.md](CLA.md) on the target branch and post its completed acceptance
   statement from your own GitHub account. Every rights holder must be covered
   before a maintainer can merge the contribution.

You keep your copyright. The agreement gives Salty Panda LLC ongoing permission
to use, modify, distribute, and license your contribution, including in commercial
releases. It does not promise compensation. If your employer owns your work,
get its authorization first. Don't accept on someone else's behalf without it.

Issues and ordinary bug reports do not require a CLA. Code or other creative
material supplied in an issue must go through the contribution process before
it is incorporated. Don't submit private scripts, credentials, signing keys,
or downloaded model weights.

## Development checks

See the [development guide](docs/DEVELOPMENT.md) for setup and speech fixtures.
The usual checks are:

```sh
swift test
./script/check_library_integration.sh
./script/build_and_run.sh --verify
```

Run only the checks relevant to your change. Documentation-only edits do not
need an app rebuild. After adding Swift source files, regenerate the Xcode
project with `python3 script/generate_project.py`.

## Maintainer merge check

- Confirm the scope and review the change.
- Verify the CLA acceptance against the exact version on the target branch.
  A checked box in the PR template is a reminder, not the acceptance record.
- Confirm that each rights holder is covered, including any employer-owned work.
- Review disclosed third-party material and retain its required notices.
- Record the acceptance comment links, the CLA document commit, and the final
  contribution commits in the PR before merging. Keep that record with the
  project history, including when squashing a PR.

This is a manual acceptance process. No CLA bot or automated merge restriction
is configured. Do not merge a contribution with missing or unclear authorization.
