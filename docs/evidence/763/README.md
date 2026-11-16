# Fixed upgrade-card geometry

All cards: 174 x 232 UI pixels, exact 3:4 like the 48 x 64 frame/splash sources. Each neighboring card has a 12-pixel gap. Three cards span 546 pixels. Full-card art uses identical bounds, nearest filtering, no crop. Inner content has a 12-pixel inset; this is not a separate cropped art region.

Cause: cards already shared fractional 176 x 234.667 bounds, but spell descriptions and extra stat rows above changed the row position. Long equipped spell names could also widen the left column. Reserve a fixed 568 x 128 stats scroll region and ellipsize long slot labels (full name on hover). Card dimensions and anchors now stay unchanged across all spell resources and all five upgrade states.

Verified actual main.tscn at 1152 x 648, short/long descriptions, locked/applied cards. All 43 harnesses pass, including added all-spell and all-state bounds/anchor assertions. The stats area above the cards scrolls. Card-description scrolling is disabled by pre-existing code. Authored production descriptions fit the inspected cards; synthetic extremely long descriptions can overflow on both base and this patch. The added synthetic-text assertions check fixed bounds and anchors only, not overflow containment or scrolling.
