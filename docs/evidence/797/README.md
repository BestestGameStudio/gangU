# Hook Shot green card splash (#797)

Daniel-approved SpriteU source master retained at tools/sprites/specs/hook-card-panorama.spriteu.json;144x64 panorama and four48x64exports in assets/sprites/ui. Three upgrade-result cards use Magnet/Catch/Rock crops. Base crop retained for future base-spell card use; current menu has no base-tier upgrade card, matching Water Shot's three-result architecture.

Reuse existing UpgradeCard applied-only texture gating, full174x2323:4bounds, nearest filtering/darkening/outlines. Locked/available/incomplete states carry no background texture. Actual main-scene upgrade screen inspected in none-applied.png and all-applied.png; all titles/body text fit.

Rock fishing description now includes the alternate anchor/lure lifecycle from PR788. Water Shot art mapping is kept separate, preserving its existing ordering and tests.
