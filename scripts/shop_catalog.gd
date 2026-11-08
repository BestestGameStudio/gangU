class_name ShopCatalog
extends Resource
## (#129, foundation C2) The set of goods a shop can sell. Mirrors the
## RewardTable idiom: one exported array of entries, contents are data.

@export var entries: Array[ShopEntry] = []
