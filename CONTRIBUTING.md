# Contributing to Teleprompter

Bug reports, fixes, documentation improvements, and focused feature contributions
are welcome. Teleprompter's first public preview is version 1.1.2 (build 4).
You can fork this repository and submit a pull request without write access to
the main repository.

The owner is the only person with write access. Every contribution needs the
owner's review and approval; see [repository access](docs/REPOSITORY_ACCESS.md).

## Report a bug

[Check existing issues](https://github.com/BitL8-ByteShort/Teleprompter/issues),
then use the [bug-report form](https://github.com/BitL8-ByteShort/Teleprompter/issues/new?template=bug_report.yml).
Include your app version/build, Mac model and memory, macOS version, playback
mode or speech engine, reproduction steps, expected behavior, and actual result.
Screenshots or short clips help when they don't reveal private script text.
Bug reports do not require a contributor agreement. Questions and feature ideas
can use a [general issue](https://github.com/BitL8-ByteShort/Teleprompter/issues/new).

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

1. Fork the repository, then create a branch from `main` in your fork.
2. Make one focused change. Include a regression test when it proves a meaningful
   behavior, especially for playback, speech alignment, or saved scripts.
3. Run the checks relevant to your change. Describe what you actually tested
   and anything you couldn't verify on your Mac.
4. Open a pull request from your fork into this repository's `main`, using the
   template. Explain the problem, the resulting
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

CLA acceptance is manual; no CLA bot checks it. Main branch rules require owner
review, but that review gate does not verify the agreement. Do not merge a
contribution with missing or unclear authorization.
