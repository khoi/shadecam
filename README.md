# ShadeCam

## Shader ABI v3

Preset shaders implement `mainImage` with the camera, mask, feedback, plate, signals, flow, and depth textures in that order. `signals` is a 256×4 `r16Float` texture: row 0 is the audio spectrum, row 1 is the audio waveform, and rows 2–3 are reserved. `flow` and `depth` are 1×1 black placeholders until their producers are active.

`iExpression` contains smoothed smile, frown, surprise, and mouth-open scores from 0–1. `iAudio` contains smoothed RMS, bass, mid, and treble levels from 0–1. Both are zero until their producers are active.

Each `iEvents` element contains envelope, seconds since trigger, and normalized trigger x/y. A never-triggered event has a time of -1. Slots are wave, clap, pinch, push, smile, two reserved slots, and debug.

Each `iHands[h][j]` and `iBody[j]` element contains normalized top-left x/y, confidence, and zero. Confidence is zero until the corresponding producer is active.

## Preset needs

Presets can start with a `/*SHADE` JSON block listing the producers they need. Valid values are `mask`, `hands`, `body`, `audio`, `expression`, `flow`, and `depth`. A preset without a block uses only the camera.

```text
/*SHADE
{"needs": ["mask"]}
SHADE*/
```
