# Subdivision Topology

## One-mesh interpretation

One mesh means one Editable Poly scene node for the requested subject. It may contain multiple intentional polygon Elements. A physically continuous surface should be one connected topological shell, while genuinely separate parts such as inserted panels, separate teeth, eye shells, or floating manufactured components may remain separate Elements inside the same node. They must be modeled topology, not hidden primitive substitutes.

Do not weld unrelated Elements just to reduce the count. Do not split one continuous skin into accidental Elements either. Record the Element count and what each Element represents. Use `requireSingleShell:true` only when the requested subject is known to require one continuous shell.

The subject geometry must originate from reviewed vertices and faces. Mental decomposition into simple volumes or cross-sections is useful for analysis, but those primitives must not be created and arranged as the model.

## Middle-poly cage

- Vertices follow meaningful cross-sections and silhouette changes.
- Face density increases only where curvature, deformation, or detail requires it.
- Edge spacing changes gradually rather than jumping abruptly.
- Support loops control edge radius and must not sit so close that they create pinching.
- Broad planar or gently curved regions remain economical.
- The cage still resembles the subject with TurboSmooth disabled.

Subdivision can produce roughly four times as many faces per iteration. One iteration is the acceptance setting. Fix the cage instead of adding iterations when the result lacks form.

## Character and creature flow

- Route closed loops around eyes and mouth, then integrate the nose, cheeks, jaw, and ears without star-like congestion in expressive areas.
- Provide directional support around eyelids and lips so openings retain thickness and can deform.
- Carry shoulder and hip flow into the torso; avoid terminating dense limb loops directly on prominent torso curvature.
- Add enough loops across elbows, knees, wrists, ankles, fingers, neck, and jaw for requested or future bending.
- Keep poles away from eyelids, mouth corners, shoulders, armpits, elbows, knees, and the main silhouette.
- Preserve joint volume. Useful deformation flow matters more than a perfectly uniform grid.

## Product, prop, and hard-surface flow

- Establish the large silhouette and planar hierarchy before cutouts, recesses, seams, or small bevels.
- Use support loops for real edge radii. Keep comparable manufactured edges visually consistent unless the reference differs.
- Terminate loops on broad low-curvature regions, not across highlight-critical corners.
- Avoid long thin quads, spiraling loops, coplanar duplicate faces, and n-gons near curved transitions.
- Use a controlled triangle only when its diagonal cannot crease or interfere with deformation.
- Model openings and thickness as connected topology when they affect silhouette or visible shading.

### Overlay Elements

Separate Polygon Elements inside one Editable Poly node are appropriate for hard-surface overlays such as access panels, armor plates, trim strips, badges, fasteners, vents, gaskets, and floating detail geometry.

- Give an overlay a deliberate surface offset, gap, recess, or physical thickness. Never duplicate a face in the same plane.
- Keep the overlay boundary and the receiving surface independently clean; do not create hidden intersections that cause shading or rendering artifacts.
- Add support loops around the overlay Element itself so one TurboSmooth iteration preserves its border and thickness.
- Use enough clearance that the smoothed overlay does not sink into or merge visually with the receiving surface.
- Keep repeated overlays consistent in edge radius, gap width, density, and normal orientation.
- Assign material IDs per Element when the reference requires different surfaces, while keeping the scene result as one Editable Poly node.
- Report overlay Elements separately in the topology summary so the Element count is explainable rather than accidental.

## Payload review

Before `max_validate_polygon_mesh`, inspect:

1. quad, triangle, and n-gon counts;
2. Element count, intended disconnected parts, and boundary/open loops;
3. edge-use count, with no edge used by more than two faces;
4. face winding for every shell;
5. isolated or duplicate vertices;
6. zero-area and near-zero-area faces;
7. centerline welds and mirrored face winding;
8. expected bounding box and proportions;
9. poles and their valence;
10. synchronous limits: 10,000 vertices, 20,000 faces, and 100,000 face-vertex references.

The semantic validator catches structural failures but cannot judge artistic edge flow. The agent must inspect planned adjacency and the rendered cage.

## Modifier and shading order

Use this non-destructive stack from bottom to top:

1. Editable Poly middle-poly cage.
2. Normal only when an A/B review proves the complete shell is flipped.
3. Smooth only when the cage has smoothing-group artifacts; use Auto Smooth at 30 degrees by default.
4. TurboSmooth with one iteration.

Add TurboSmooth through `max_add_modifier` with this parameter plan:

```json
{
  "modifier": "TurboSmooth",
  "parameters": {
    "iterations": 1,
    "useRenderIterations": false,
    "isolineDisplay": true,
    "smoothResult": true
  }
}
```

Do not collapse the stack. With `useRenderIterations:false`, the single viewport iteration is also used for rendering. Move support loops or change cage topology rather than increasing iterations.

## Visual review

Use maximized screenshots with identical framing:

- front or principal orthographic view for proportions;
- side orthographic view for depth and profile;
- three-quarter perspective for volume and highlight flow;
- close views of the face, hands, joints, openings, corners, or other topology-critical regions;
- cage view before TurboSmooth and smooth shaded view after TurboSmooth.

Reject the result when TurboSmooth introduces pinching, waviness, melted corners, collapsed openings, asymmetrical drift, dents, or silhouette loss. Return to the base arrays, validate the revised payload, and rebuild. A clean render cannot compensate for incorrect topology.

Official references:

- [Smooth modifier MAXScript properties](https://help.autodesk.com/cloudhelp/2021/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Modifier-MAXWrapper-and/Modifier-and-SpacewarpModifier/Modifiers/Mesh-Editing/GUID-2147DA88-06E0-4F90-B358-E98011E776B6.html)
- [TurboSmooth modifier MAXScript properties](https://help.autodesk.com/cloudhelp/2021/ENU/3DSMax-MAXScript/files/GUID-05FAC300-EED9-4999-8B9F-4EE4E87E19A4.htm)
