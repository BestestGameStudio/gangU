# Raptor animation retrospective

The SpriteU pass produced a run, an eating animation, a spinning tail smack, and a roar. The roar was the first pass to render its key poses as primary-color silhouettes with a separate swatch for each visible part.

- **Preserve the character before animating it.** The first run read clearly, but its simplified palette and shorter neck changed the character. Sampling the original sprite restored the head shape, texture, and underside markings. The stride kept its eight-frame, 480 ms cadence.
- **Track a landmark through the motion.** The run's neck looked like it slid forward and back. Keeping the skull at a fixed horizontal position and shifting the flex into the neck and shoulders steadied the head while preserving the stride.
- **Inspect parts before shading.** On the roar, the bright arm patch made a detached forearm easy to identify. The colored poses also showed where the jaw opened and the tail counterbalanced the lifted chest. The finished frames kept the same occupied pixels as the blocked frames.
- **Check what the export actually plays.** A contact sheet showed clipping and silhouette problems. Decoding the GIF confirmed transparency, frame order, and timing. The tail smack used a 40 ms smear and a 70 ms contact hold to make the swing feel fast and the landing feel heavy.

The [color silhouette animation skill](../.agents/skills/color-silhouette-animation/SKILL.md) captures the workflow for future sprites.
