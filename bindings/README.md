# Python binding (macOS)

`thestage_sdk` runs the SDK's models from Python on Apple Silicon Macs: language
models with chat sessions and tools, vision-language models, speech recognition,
text to speech, the voice agent, and a local OpenAI-compatible server.

```
bindings/
├── swift/     Swift package: TheStageBridge and the thestage-host helper
└── python/    thestage_sdk (asyncio client, NumPy audio)
```

Python sends calls to `thestage-host`, a native helper built from `swift/` against
the `TheStageSDK` package at the root of this repository, so the models run at
native speed.

## Build and install

Requirements: macOS 15 or later on Apple Silicon, Python 3.10 or later, Xcode 16 or
later (for the one-time build of the helper).

```bash
cd bindings/python
pip install wheel
./scripts/build_wheel.sh
pip install dist/thestage_sdk-*.whl
```

`build_wheel.sh` builds `thestage-host` in release, signs it (ad hoc, or with the
Developer ID named in `THESTAGE_SIGN_IDENTITY`) and puts it inside the wheel. The
wheel then needs no Xcode or Swift where it is installed.

Start with [`python/README.md`](./python/README.md); the pages are in
[`python/docs/`](./python/docs/README.md) and runnable scripts in
[`python/examples/`](./python/examples/).
