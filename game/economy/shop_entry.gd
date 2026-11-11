class_name ShopEntry
extends Resource
## (#129, foundation C2) One purchasable good + its price. Data-driven, so
## catalog contents and prices live in .tres data, never in code. Contents
## and prices are PLACEHOLDER data only (final pricing is human-open, #129).

## The good being sold. A Spell today; consumable/relic resources plug in
## when the C3/C4 grant seams land (dispatch by type in shop.gd).
@export var good: Resource
## Price in run currency (#128 wallet). Must be > 0 to be purchasable.
@export var price: int = 0
