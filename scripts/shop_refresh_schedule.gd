class_name ShopRefreshSchedule
extends Resource
## (#132, foundation C5) Paid stock-refresh price schedule. DATA-driven so
## the curve stays human-open: the two seed prices are exported resource
## data, and growth continues by summing the previous two - the Fibonacci
## rule Daniel confirmed verbatim (2026-11-08, "fibonacci yeah" to
## "1, 2, 3, 5, 8, 13, 21 and keep growing that way"). His original
## example "1 > 2 > 3 > 5 > 8" is the default seed pair (1, 2).
##
## price_at(0) is the FIRST purchase's price; the shop's victory reset
## returns the counter to 0, so the schedule itself carries no state.

## Price of the first paid refresh after a reset.
@export var first_price: int = 1
## Price of the second paid refresh after a reset.
@export var second_price: int = 2

func price_at(index: int) -> int:
	if index <= 0:
		return first_price
	var a := first_price
	var b := second_price
	for i in range(1, index):
		var next := a + b
		a = b
		b = next
	return b
