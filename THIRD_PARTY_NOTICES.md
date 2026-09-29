# Third-party notices

Teleprompter is maintained by Salty Panda LLC under the project's proprietary
license. The libraries and models below keep their own terms. Teleprompter's
license and contributor agreement do not replace or restrict those rights.

Full license texts and copyright notices are included in [Core/Licenses](Core/Licenses).
That folder ships inside the signed app as `Contents/Resources/Licenses` and
beside the app on the installer disk image. Open **Help → Licenses & Credits**
to read the documents offline. The app also includes Teleprompter's own license.

## Libraries included in the app

| Component | Pinned version | Included terms and notices |
| --- | --- | --- |
| MoonshineVoice and Moonshine native library | 0.1.5 | [Moonshine license and scope](Core/Licenses/Moonshine/LICENSE.txt), MIT for the code and English streaming models |
| FluidAudio | 0.17.4 | [Apache 2.0](Core/Licenses/FluidAudio/LICENSE.txt) and the upstream `ThirdPartyLicenses` documents in the same folder |
| WhisperKit / Argmax OSS | 1.1.0 | [MIT](Core/Licenses/Argmax/LICENSE.txt) and [NOTICES](Core/Licenses/Argmax/NOTICES.txt), including Hugging Face swift-transformers attribution and full Apache 2.0 text |
| Swift Argument Parser | 1.8.2 | [Apache 2.0 with Swift exception](Core/Licenses/SwiftArgumentParser/LICENSE.txt) |

Moonshine's static framework includes ONNX Runtime (the framework reports
1.23.0), cpp-annote, Eigen's MPL-only subset, kaldi-native-fbank, KISS FFT,
nlohmann/json, UTF-8, and utf8proc. Their full license texts are in
`Core/Licenses/Moonshine/`, together with ONNX Runtime's third-party notices.
The upstream notice list is retained in full; some listed optional components
are not used by this Mac build. The vendored doctest license is also retained.

Eigen's covered source remains under MPL-2.0. Its corresponding source is
available at no charge from the exact Moonshine source revision identified in
[Eigen-Source-Availability.txt](Core/Licenses/Moonshine/Eigen-Source-Availability.txt).
Teleprompter does not modify that source. Its proprietary terms do not limit
the rights MPL-2.0 grants in those files.

FluidAudio's NemoTextProcessing binary is pinned to the v0.3.1 artifact. Its
Apache license, NOTICE, NVIDIA NeMo attribution, and full license texts for the
Rust dependency graph are included under `Core/Licenses/NemoTextProcessing/`.
The graph includes platform and optional dependencies; retaining those notices
does not mean every component executes on macOS. Dual-licensed components may
be used under their MIT or Apache option. FluidAudio's upstream notices for
fastcluster, VBx, and text frontends are preserved as well, including components
outside Teleprompter's speech-to-text features.

## Optional model downloads

The installer includes model license documents, but no model weights.
Apple Speech is the default. Other models download only when requested.
Their terms are copied into a `Licenses` folder beside the downloaded files
before downloading weights. Models installed by an earlier Teleprompter release
receive those documents when first used, without changing their weights.

| Model used by Teleprompter | Included terms |
| --- | --- |
| Moonshine English Small Streaming | [Moonshine license](Core/Licenses/Models/Moonshine/LICENSE.txt), Section 1 MIT. The upstream document is retained verbatim; its Section 2 restrictions apply to the enumerated legacy non-English models, which Teleprompter does not download. |
| Parakeet Realtime EOU 120M, 320 ms Core ML conversion | [NVIDIA Open Model License](Core/Licenses/Models/Parakeet/NVIDIA-Open-Model-License.txt), the unmodified official PDF, incorporated Trustworthy AI terms, [model card](Core/Licenses/Models/Parakeet/Model-Card.md), and required [Notice.txt](Core/Licenses/Models/Parakeet/Notice.txt) |
| Whisper Large v3 Turbo, `openai_whisper-large-v3-v20240930_626MB` Core ML conversion and tokenizer | [OpenAI MIT license](Core/Licenses/Models/Whisper/OpenAI-MIT.txt) and [Argmax MIT notice](Core/Licenses/Models/Whisper/Argmax-MIT.txt) |

Parakeet attribution: Licensed by NVIDIA Corporation under the NVIDIA Open Model License.

Apple Speech is supplied by macOS. Teleprompter does not package Apple's speech
models. Apple software remains subject to Apple's applicable terms.

## Provenance and release checks

[manifest.json](Core/Licenses/manifest.json) records dependency revisions,
binary artifact checksums, source URLs, and the SHA-256 of each bundled document.
Package licenses come from the pinned source checkouts. Moonshine's additional
notices come from its v0.1.5 source revision. Rust crate notices come from the
versions in the NemoTextProcessing release lockfile, with source archive
checksums verified against that lockfile. Where a crate omits its license file
from its archive, its upstream revision or declared Apache 2.0 terms are retained.
The NVIDIA agreement PDF is copied unchanged from NVIDIA's official site;
plain-text versions are included for offline reading.

The installer script checks both resolved package files against this inventory,
verifies every document's checksum, and checks the exported app's copies before
creating the DMG. Changing dependency versions requires updating the inventory
and notices. These documents cover the versions and model variants identified
above; new dependencies or variants need their own terms.
