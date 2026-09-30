# Signing and Apple's malware check

Teleprompter **1.1.2, build 4** is signed by **Salty Panda LLC** using Apple's
Developer ID program and is notarized by Apple. The notarization ticket is
attached to the app. On September 29, 2026, its signature and attached ticket
validated, and macOS Gatekeeper accepted it as `Notarized Developer ID`.

Apple's automated notarization service checks submitted software for known
malware and signing problems. A notarized build passed those checks; this is not
a guarantee against every threat or a full security audit. See
[Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Suggested wording for this release:

> Teleprompter 1.1.2 is signed by Salty Panda LLC and notarized by Apple. Apple's
> automated checks found no known malware in this build.

We have not submitted the app to the Mac App Store or completed an independent
security audit. Distribution uses the first public preview's GitHub release DMG.
The **app inside the DMG** is signed and notarized; the disk-image container does
not have a separate signature or notarization ticket.

## Verify this release

- Bundle identifier: `com.bitl8byteshort.Teleprompter`
- Signing team: `4WWK6TTABC` (Salty Panda LLC)
- Installer: `Teleprompter-1.1.2-arm64.dmg`
- SHA-256: `dc4414e9fdde5befd8ecf65f97d6729c4953d4c34b6d693866097b1909167f1b`
- [First public preview](https://github.com/BitL8-ByteShort/Teleprompter/releases/tag/v1.1.2-public-preview.1)

To verify an installed copy:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Teleprompter.app
xcrun stapler validate /Applications/Teleprompter.app
spctl --assess --type execute -vv /Applications/Teleprompter.app
```

These checks verify this copy's signature, notarization ticket, and Gatekeeper
assessment. If the app changes, it must be signed and notarized again before a
new release can make the same claim. See [packaging instructions](PACKAGING.md).
