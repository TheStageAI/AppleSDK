# Licensing & Device Identity

How seats work when your app embeds the TheStage Apple SDK.

Commercial terms and pricing are in the
[TheStage Apple SDK Product Terms](./product_terms.md) — contact TheStage AI
for quotes. This page is the integrator-facing product summary only.

## Initialize registers the device

Call once before any pipeline / `start_model`:

| Surface | Call |
|---|---|
| Swift | `try await TheStageAI.shared.initialize(apiToken: "…")` |
| Flutter | `await TheStageFlutterSDK.initialize(api_token: '…')` |

A successful initialize **registers the device** with TheStage (online
validation). Pipelines throw if the SDK has not been initialized.

## Seat = `(apiToken, deviceId)`

A billable **Device Seat** is the pair `(apiToken, deviceId)`:

- **`apiToken`** identifies the customer. Different tokens on the same
  physical phone or Mac are different seats.
- **`deviceId`** identifies the registered device for that token.

**Product guarantee:** reinstalling the **same app** on the **same device**
is intended to keep the **same seat** (not a new charge for that pair).

Seat counts, plan limits, and overages are defined in your commercial
arrangement with TheStage — not in this page.

## Offline / network

`initialize` requires a successful online token validation. If the device
is offline or the backend is unreachable, initialize fails — reconnect and
call `initialize` again. After a successful initialize in the same process,
inference runs fully on-device (no further phone-home for that session).

## Agent checklist

- Always `initialize` before constructing pipelines or calling `start_model`.
- One seat = `(apiToken, deviceId)`; do not invent your own device registry.
- For pricing / seat plans → open a **Service Request** at
  [app.thestage.ai/contact](https://app.thestage.ai/contact).
- Do not document or depend on internal ID derivation or backend field
  names — those are not part of the public contract.
