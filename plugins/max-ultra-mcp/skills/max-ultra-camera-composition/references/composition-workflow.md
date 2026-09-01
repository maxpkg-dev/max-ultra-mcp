# Camera Composition Workflow

## Establish the final frame

Read production width and height before positioning the camera. Preserve exact pixel dimensions for verification because portrait, landscape, square, panoramic, and vertical-social formats need materially different framing.

Safe Frame is derived from the production render aspect. Its outer live-area boundary is the authoritative composition edge. Inner action/title guides are delivery-safety guides, not automatic still-image crop rules.

After activating the intended camera, enable Safe Frame deterministically:

```maxscript
(
    local safeFramesWereEnabled = displaySafeFrames
    displaySafeFrames = true
    completeRedraw()
    #(safeFramesWereEnabled, displaySafeFrames)
)
```

The returned second value must be `true`. Do not use a toggle because a retry could disable an already-correct state. If screenshot metadata does not identify the intended camera, reactivate it and repeat the check before moving anything.

## Plan before applying

Define these constraints before changing the camera:

- primary and optional secondary subjects;
- output dimensions and aspect;
- desired composition pattern;
- camera height, horizon, and vertical-line behavior;
- required context versus tightness;
- protected empty space for text or graphics;
- objects that may be cropped and objects that must remain complete;
- lens or perspective constraints supplied by the user.

Use a subject bounding box as evidence, not as an instruction to center everything. Place the actual visual focal point according to the composition, then leave room for dominant direction, motion, gaze, entrances, or leading lines.

### Single-object framing

When there is exactly one newly created or explicitly isolated object and the user gives no different composition:

1. Measure that object's world bounding box after all requested modeling and modifier changes.
2. Aim at the bounding-box center.
3. Center the object horizontally and vertically within the outer Safe Frame.
4. Move the camera or adjust the lens until every bounding-box corner fits inside the rendered live area.
5. Keep an even visual margin on all sides and re-check after the viewport is maximized.
6. Capture with unrelated geometry and selection artifacts excluded from the framing decision.

This mode takes precedence over thirds, leading-room, and intentional-crop guidance. The complete object is the subject and must not be clipped.

## Iterative visual score

Compare candidates at the same render aspect and viewport preset:

1. Subject coverage gives the subject the intended visual weight.
2. Edge clearance avoids accidental clipping or frame tangencies.
3. Focal hierarchy leads the eye to the primary subject first.
4. Visual mass and negative space feel intentional.
5. Lens distortion and depth compression fit the task.
6. Architectural verticals, horizon, and proportions remain credible.
7. Foreground and background support rather than obscure the subject.
8. Bright patches, helpers, selection artifacts, and unrelated objects do not dominate.

For single-object framing, add a hard pass/fail check: all projected object bounds remain inside Safe Frame and the object's projected center aligns with the frame center.

Make one small correction per iteration so its effect can be evaluated. Prefer position, distance, yaw/pitch, then lens or FOV when applicable. Explicit user constraints take precedence over this ordering.

## Camera creation and property edits

Create a free camera with `max_create_primitive` and retain its NodeRef. Use `max_transform_object` for explicit positions and Euler rotations. When a property is not represented by a semantic tool, use a short `max_run_script` block that:

- resolves the camera by handle rather than name alone;
- verifies the node still exists and is a camera;
- checks `isProperty` before setting a property;
- changes only reviewed properties in one undo transaction;
- returns actual applied values.

Never paste raw user prose into MaxScript or guess renderer-specific properties. If exact lens, FOV, shift, or clipping behavior cannot be verified through capability or property introspection, report it as unsupported instead of claiming success.

## Evidence and handoff

The accepted result should include:

- camera NodeRef and exact name;
- final position and rotation;
- final supported lens or FOV value;
- render width, height, and aspect;
- confirmation that Safe Frame is enabled;
- chosen composition pattern and intentional crops;
- a maximized clean-realistic camera screenshot with Safe Frame visible;
- remaining uncertainties or renderer-specific settings not applied.

Leave Safe Frame enabled on the accepted camera view so the user sees the same boundary when continuing manually.
