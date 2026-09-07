# Armrests and Upholstery

## Armrests and frame

Reconstruct the top contour independently from the side profile. Track varying width, front and rear endings, thickness, top convexity, underside slope/curvature, and overhangs. Define cross-sections at the front, attachments, middle, and rear, adding sections where the observed form changes. Solve transitions into supports and distinguish front/rear endings; do not assume they are identical. Mirror left/right only when supported by the product's symmetry.

Compare a closeup from the same side for contour, thickness, and highlight flow. A generic rounded box cannot stand in for an elongated armrest whose width and sections change along its length. Material contour errors must be fixed before detailing. Frame members likewise need their actual taper, bend, end radii, physical edge radii, contact, and joinery. Section and support-loop placement should describe those forms economically, with no pinching after one smoothing iteration.

## Support loops for one-iteration TurboSmooth

An unsupported edge can round over substantially under TurboSmooth. Support loops closer to the edge generally produce a narrower, firmer transition; wider spacing produces a broader, softer transition. The result also depends on neighboring topology and physical scale, so derive spacing from the reference's edge radius rather than a universal offset.

Place deliberate support loops along the contour and near ends, corners, and joints of hard frame members. At a leg's lower end, support both the sidewall and the cap perimeter so the smoothed end retains its intended cross-section and physical bevel. Use clean connected cap topology with consistent winding, no degenerate faces, and no poles or n-gons that pinch the curved transition. Blend loop density gradually into the rest of the member. Extremely close loops are not a substitute for a designed radius: avoid nearly zero-width strips, pinching, and shading artifacts. For soft upholstery, retain broader transitions where the reference supports them instead of imposing a hard box-like rim.

Cut, Swift Loop, and Connect are possible UI construction methods, not required tools. Through MCP, build equivalent topology with available semantic operations or reviewed vertex/face data; do not force UI interaction when the geometry can be created directly.

Compare unsmoothed and one-iteration smoothed views at identical framing, including a closeup of the lower leg end. Verify the cross-section, end shape, bevel width, and highlight continuity without collapse or sharp creases. Correct loop placement and count, cap flow, or neighboring topology when the comparison fails; do not increase iterations to conceal the defect.

## Upholstery volume

Separate the base, filling thickness, crown/curvature in both principal directions, sidewall, and transition into the seam. Reproduce contact/compression against the frame and between seat and back. Determine which fabric is taut and which is loose. A broad flat slab with rounded borders fails a volumetric reference, while uniform inflation of every panel fails taut, tailored upholstery. Check silhouette, sections, and highlights before folds.

## Subtle folds after primary form passes

Use intentional local edge/quad strips along plausible tension or compression near seams, corners, and supports. Shape each fold across its width as a shallow trough with a soft adjacent shoulder; neighboring rows should carry a smooth transition into the original surface. Displace along the local surface direction/normal, not global Z. Taper width and depth smoothly to zero at the ends.

Vary length, amplitude, and spacing according to the observed fabric. Avoid regularly alternating raised/lowered rows, corrugation, random noise, sharp cuts, ballooning, or gratuitous wrinkles on taut fabric. Anchor the amount to reference and physical scale, not universal numerical amplitudes. Preserve cushion volume and support flow, and inspect for pinching after exactly one smoothing iteration.

## Seam, piping, and stitching

Identify each treatment from a closeup: recessed panel join, pinch, corded piping, or visible stitching. Follow the actual panel cutting pattern, corners, ends, and concealed continuation; do not automatically repeat one contour on every cushion side.

- Recessed seams need integrated surface transitions and controlled width/depth that survive subdivision.
- Piping needs its observed section, clearance, and attachment, as an intentional Element where physically separate. Do not replace every seam with a tube.
- Stitching uses threads or a surface map according to requested scope and viewing distance, at a small physical scale and in contact with the fabric. Do not invent decorative stitches.

Inspect a straight section, corner, and ending at close range. A dark Material ID line alone is not a completed recessed seam. Keep the geometry-only boundary when a surface-map finish was not requested.
