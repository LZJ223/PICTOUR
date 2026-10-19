# v2 局部修改提示词

方式：内置 imagegen。唯一编辑目标：PICTOUR_KeyArt_3840x2160.png。保留原版，去除断桥并校正地面与纸页透视。

Use case: precise-object-edit.
Image 1 is the EDIT TARGET: the existing game promotional illustration. Make a targeted revision to this same artwork, not a new composition.

Primary changes requested:
1. REMOVE the broken-bridge element entirely: erase the diagonal sequence of narrow, grass-topped floating ledges / disconnected bridge sections across the center. Do not merely fill in their gaps to create another bridge, and do not replace them with stepping stones, stairs, a boardwalk or floating platforms.
2. In that central region, depict broad, calm, unbroken grassy forest clearings belonging naturally to their respective illustrated paper layers. Each layer's ground should read as a continuous piece of its forest scene, rather than a narrow structure spanning between layers. Keep the layers visually distinct through their paper edges, overlaps, scene scale and depth, not through a hazardous broken pathway.
3. Correct spatial construction and perspective throughout the affected area. Use one consistent horizon and coherent vanishing directions for the ground surfaces, the upright paper panels, the houses, and the open book. Each upright scenery panel must be visibly rooted in its corresponding page or base plane; its lower edge and grass plane must meet convincingly. Ground planes must recede logically, near objects overlap farther ones correctly, and parallel edges must obey the same perspective system. No impossible kinks, contradictory plane orientations, or floating terrain strips. Preserve the intentional flat 2.5D layered-paper stage look rather than turning this into a realistic 3D landscape.

Strict invariants:
- KEEP the overall existing composition, framing and camera angle: large open picture book sweeping along the bottom, robot in the left foreground, small floating Book Spirit beside and above it, large geometric trees framing the left, layered forest pages fanning into depth across the middle and right, houses and distant waterfall in their general existing positions.
- Keep the prominent open book and its curved layered page edges. Keep the tall separated picture-book scene panels, cream/white paper outlines and clear depth layering. These are the central appealing elements and must not be removed.
- Preserve the robot's exact current identity, muted blue-gray color, relative size, head/body/track proportions, three visible wheels, small propeller bar and narrow white oval LED eyes. No new arms, legs, mouth or redesign. It remains securely grounded on the foreground grass.
- Preserve the floating brown Book Spirit's eyes, cream page stack, brown/red cover, sticker outline, pose and relative position. No extra characters.
- Preserve the existing bright cyan sky, vivid greens, warm paper and brown palette; black slightly wobbly hand-drawn contours, white sticker edges, selective halftone polka dots, flat color and two-tone shadows. Do not change the art style or add photorealistic rendering.
- Keep all unaffected details as close to Image 1 as possible. Do not zoom, crop, relocate or substantially rescale the focal characters, book, major trees or main scene panels.

Output: opaque landscape, exact 16:9, preferably 3840 x 2160; no border.
Text: NONE. No writing, title, letters, numbers, logo, captions, watermark, UI, buttons, speech bubbles or diagram arrows.
Avoid: any bridge silhouette, disconnected grass-topped slabs, floating stepping platforms, a new central chasm, a replacement staircase, reshuffled composition, character redesign, perspective contradictions.
