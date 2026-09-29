# Third-party licensing

Teleprompter's [proprietary license](LICENSE) covers its own material. Libraries,
models, and other third-party components keep their separate licenses and
copyright notices. A contribution agreement cannot change rights in someone
else's work.

The current direct dependencies are pinned in `Package.resolved`:

| Component | Version / variant | Upstream terms |
| --- | --- | --- |
| MoonshineVoice | Swift package 0.1.5 and its Moonshine binary | [Moonshine licensing](https://github.com/moonshine-ai/moonshine/blob/main/LICENSE); embedded third-party components have separate terms |
| FluidAudio | 0.17.4 | [Apache 2.0](https://github.com/FluidInference/FluidAudio/blob/21493f8dac5a97e65742e6ff26f42f164c2fda0f/LICENSE) and its `ThirdPartyLicenses` directory |
| WhisperKit / Argmax OSS | 1.1.0 | [MIT](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/LICENSE) and [NOTICES](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.0/NOTICES) |
| Swift Argument Parser | 1.8.2, in the resolved dependency graph | [Apache 2.0 with Swift exception](https://github.com/apple/swift-argument-parser/blob/1.8.2/LICENSE.txt) |

Optional models download separately:

| Model used by the app | Upstream terms |
| --- | --- |
| Moonshine English Small Streaming | [MIT, as specified by Moonshine](https://github.com/moonshine-ai/moonshine/blob/main/LICENSE) |
| Parakeet Realtime EOU 120M, 320 ms Core ML conversion | [Model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) and [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) |
| Whisper Large v3 Turbo, WhisperKit Core ML conversion | [MIT model repository](https://huggingface.co/argmaxinc/whisperkit-coreml) |

Apple Speech is supplied by macOS. Teleprompter does not package Apple's speech
models; Apple software remains subject to Apple's applicable terms.

## Distribution status

This file identifies sources and terms; it is not a complete bundle of license
texts or a completed audit of the shipped binaries. The existing private 1.1
installer predates these repository documents and has not been repackaged here.

Before distributing a new installer outside private testing, review the exact
resolved packages, embedded binary components, and downloaded model variants.
Include all required license texts, copyright notices, and attribution with the
relevant distributed components. In particular, NVIDIA's terms require a copy
of its agreement and its specified notice when redistributing its model.
Links in this file do not replace those obligations.
