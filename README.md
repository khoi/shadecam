# ShadeCam

## Shader ABI v3

Preset shaders implement `mainImage` with these textures:

| Index | Name | Contents |
| ---: | --- | --- |
| 0 | `camera` | Live camera frame |
| 1 | `mask` | Person segmentation mask |
| 2 | `feedback` | Previous rendered frame |
| 3 | `plate` | Captured background frame |
| 4 | `signals` | 256×4 `r16Float`; audio spectrum, waveform, then two reserved rows |
| 5 | `flow` | Two-component camera-pixel displacement vectors |
| 6 | `depth` | Normalized relative inverse depth; 1 ≈ nearest, 0 ≈ farthest |

`flow` and `depth` are 1×1 black placeholders until their producers are active. Shaders can guard access with `texture.get_width() <= 1`. Divide flow texels by the flow texture dimensions before applying them as UV offsets.

`plate` has zero alpha until the user captures a background and full alpha afterward. Sample its alpha to choose a no-plate fallback.

`iExpression` contains smoothed smile, frown, surprise, and mouth-open scores from 0–1. `iAudio` contains smoothed RMS, bass, mid, and treble levels from 0–1. Both are zero until their producers are active.

Each `iEvents` element contains envelope, seconds since trigger, and normalized trigger x/y. A never-triggered event has a time of -1. Slots are wave, clap, pinch, push, smile, two reserved slots, and debug.

Each `iHands[h][j]` and `iBody[j]` element contains normalized top-left x/y, confidence, and zero. Confidence is zero until the corresponding producer is active.

Hand 0 is left and hand 1 is right. Unknown chirality is assigned by wrist x, leftmost first. Joint indices are 0 wrist; 1–4 thumb CMC, MP, IP, tip; 5–8 index MCP, PIP, DIP, tip; 9–12 middle MCP, PIP, DIP, tip; 13–16 ring MCP, PIP, DIP, tip; and 17–20 little MCP, PIP, DIP, tip.

| `iBody` index | Joint |
| ---: | --- |
| 0 | nose |
| 1 | leftEye |
| 2 | rightEye |
| 3 | leftEar |
| 4 | rightEar |
| 5 | neck |
| 6 | leftShoulder |
| 7 | rightShoulder |
| 8 | leftElbow |
| 9 | rightElbow |
| 10 | leftWrist |
| 11 | rightWrist |
| 12 | root |
| 13 | leftHip |
| 14 | rightHip |
| 15 | leftKnee |
| 16 | rightKnee |
| 17 | leftAnkle |
| 18 | rightAnkle |

## Preset needs

Presets can start with a `/*SHADE` JSON block listing the producers they need and optional interaction instructions shown in the editor. Valid needs are `mask`, `hands`, `body`, `audio`, `expression`, `flow`, and `depth`. A preset without a block uses only the camera.

```text
/*SHADE
{"needs": ["mask"], "instructions": "Step into frame."}
SHADE*/
```
