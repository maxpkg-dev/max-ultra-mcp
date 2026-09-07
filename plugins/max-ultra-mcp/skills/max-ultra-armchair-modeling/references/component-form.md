# Armrests and Upholstery

## Armrests and frame

Reconstruct the top contour independently from the side profile. Track varying width, front and rear endings, thickness, top convexity, underside slope/curvature, and overhangs. Define cross-sections at the front, attachments, middle, and rear, adding sections where the observed form changes. Solve transitions into supports and distinguish front/rear endings; do not assume they are identical. Mirror left/right only when supported by the product's symmetry.

Compare a closeup from the same side for contour, thickness, and highlight flow. A generic rounded box cannot stand in for an elongated armrest whose width and sections change along its length. Material contour errors must be fixed before detailing. Frame members likewise need their actual taper, bend, end radii, physical edge radii, contact, and joinery. Section and support-loop placement should describe those forms economically, with no pinching after one smoothing iteration.

### Truly rectangular rails and boards

Use the simplest construction that matches the real part. A straight rectangular rail or board of constant section may start as a Box, converted to an editable cage with the necessary small bevels and support loops for one-iteration TurboSmooth. An equivalent simple polygon mesh is equally valid; no particular UI tool is required. This exception does not justify replacing a changing-section armrest or volumetric cushion with a generic box.

Preserve flat sides, straight edges, constant section, and clean ends in the part's local geometry. Set its overall angle and placement with a rigid object transform, not independent vertex dragging, warping, or projection onto another surface. Derive dimensions, bevel radius, and angle from the reference; no fixed example angle is a default. Verify the transformed part's section and end shape before and after smoothing. During final attachment, preserve the rigid placement and keep the part as an intentional Element in the one Editable Poly cage with live TurboSmooth.

For ordinary archviz joints, use a plausible end-to-side or end-to-support fit with readable part boundaries and small physical bevels on the appropriate exposed hard edges, not the same chamfer on every surface. Require real contact or a small construction gap supported by the reference; do not separate all parts with floating gaps or let them visibly penetrate deeply. Hidden overlap is not an excuse for visible intersections. Build complex interlocking joinery, mortise-and-tenon details, or concealed fasteners only when visible in the reference or explicitly requested; Boolean continuity is unnecessary for a simple contact joint. Check the fit after one TurboSmooth iteration for floating, clipping, coplanar duplicates, and z-fighting. Keep physically separate parts as separate Elements in the final Editable Poly; do not force-weld them together.

## Loops must define the form

Keep genuinely flat, unchanging regions economical; extra edges add no shape there. Preserve the connectivity and topology needed for stable subdivision. Increase density where silhouette, curvature, seams, folds, or transitions require it, not only at sharp edges. Distinguish shape-defining loops that describe broad soft curvature from tightly spaced support loops that hold a narrow transition.

At a rounded corner or changing section, inserting cuts alone does not reconstruct the form. Position the new vertices on the reference-derived volumetric profile in local profile/surface directions, not only global Z. Leaving them coplanar on the old flat face can retain flat patches and faceted corners despite a high polygon count. Vary loop spacing and edge flow gradually; keep edge concentrations and poles away from highlight-critical soft corners. Compare the cage profile and its intended tangent progression with the one-iteration surface, checking smooth highlights and preserved volume. Correct vertex positions and flow instead of masking defects with more iterations.

## Support loops for one-iteration TurboSmooth

An unsupported edge can round over substantially under TurboSmooth. Support loops closer to the edge generally produce a narrower, firmer transition; wider spacing produces a broader, softer transition. The result also depends on neighboring topology and physical scale, so derive spacing from the reference's edge radius rather than a universal offset.

Place deliberate support loops along the contour and near ends, corners, and joints of hard frame members. At a leg's lower end, support both the sidewall and the cap perimeter so the smoothed end retains its intended cross-section and physical bevel. Use clean connected cap topology with consistent winding, no degenerate faces, and no poles or n-gons that pinch the curved transition. Blend loop density gradually into the rest of the member. Extremely close loops are not a substitute for a designed radius: avoid nearly zero-width strips, pinching, and shading artifacts. For soft upholstery, retain broader transitions where the reference supports them instead of imposing a hard box-like rim.

Cut, Swift Loop, and Connect are possible UI construction methods, not required tools. Through MCP, build equivalent topology with available semantic operations or reviewed vertex/face data; do not force UI interaction when the geometry can be created directly.

Compare unsmoothed and one-iteration smoothed views at identical framing, including a closeup of the lower leg end. Verify the cross-section, end shape, bevel width, and highlight continuity without collapse or sharp creases. Correct loop placement and count, cap flow, or neighboring topology when the comparison fails; do not increase iterations to conceal the defect.

## Upholstery volume

Separate the base, filling thickness, crown/curvature in both principal directions, sidewall, and transition into the seam. Reproduce contact/compression against the frame and between seat and back. Determine which fabric is taut and which is loose. A broad flat slab with rounded borders fails a volumetric reference, while uniform inflation of every panel fails taut, tailored upholstery. Check silhouette, sections, and highlights before folds.

On broad soft surfaces, distribute edges relatively evenly with gradual spacing changes that follow curvature; do not demand a strictly uniform grid everywhere. Add local density where the observed silhouette, curvature, seams, folds, or transitions require it, then blend it into the surrounding surface. Do not transfer the tight support-loop pattern of hard legs automatically to upholstery: several tight parallel strips or an edge concentration at a soft corner can create an unintended cinch or hard bevel. Redistribute unnecessary support into the surrounding curvature while preserving the real seam. After one TurboSmooth iteration, inspect a broad, smoothly flowing highlight and preserved cushion volume, with no pinching or artificial chamfer band around the cushion.

## Subtle folds after primary form passes

Use intentional local edge/quad strips along plausible tension or compression near seams, corners, and supports. Shape each fold across its width as a shallow trough with a soft adjacent shoulder; neighboring rows should carry a smooth transition into the original surface. Displace along the local surface direction/normal, not global Z. Taper width and depth smoothly to zero at the ends.

Vary length, amplitude, and spacing according to the observed fabric. Avoid regularly alternating raised/lowered rows, corrugation, random noise, sharp cuts, ballooning, or gratuitous wrinkles on taut fabric. Anchor the amount to reference and physical scale, not universal numerical amplitudes. Preserve cushion volume and support flow, and inspect for pinching after exactly one smoothing iteration.

## Seam, piping, and stitching

First determine from a closeup whether the seam stands proud of the surface or recedes into it, and distinguish an integrated raised seam, recessed panel join, pinch, separate corded piping, and visible stitching. Follow the actual panel cutting pattern, corners, ends, and concealed continuation; do not automatically repeat one contour on every cushion side.

- For an integrated raised seam, build a finite-width strip along the seam loop and shape its cross-section outward along the local surface normal, with reference-derived width and height. Give the profile shoulders a physical bevel or support appropriate to its scale. It may be rounded-rectangular or another observed section; a square seam is not universal. Keep it connected to the surrounding surface without accidental overlaps; welding adjacent panels into a flat line does not create the raised profile. Edge-loop/extrude/chamfer describes one construction approach, but equivalent strip/profile vertex-and-face topology is sufficient through MCP. Do not extrude a bare edge into a zero-width or non-manifold strip.
- For a recessed seam, form a local groove inward relative to the surface with smooth fabric-tension transitions into neighboring rows. Check its width and depth after one TurboSmooth iteration so it neither disappears nor becomes a sharp cut.
- Physically separate piping may be an intentional Element with its observed section, real contact, clearance, and attachment to the fabric. Do not arbitrarily attach a universal tube in place of the reference seam.
- Stitching uses threads or a surface map according to requested scope and viewing distance, at a small physical scale and in contact with the fabric. Do not invent decorative stitches.

Inspect a straight section, corner, and ending at close range. A dark Material ID line alone is not a completed recessed seam. Keep the geometry-only boundary when a surface-map finish was not requested.
