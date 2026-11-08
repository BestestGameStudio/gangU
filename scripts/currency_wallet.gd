class_name CurrencyWallet
extends Node
## Run-scoped currency wallet (#128, foundation C1): balance + add + spend
## with a balance-changed signal for future UI (hub shop is #129+). Mounted
## ONCE on Main, same pattern as ReviveSatchel/RewardPool; per-run reset
## comes free from RunManager's full scene reload - no reset code here. A
## retained revive item lives on the sibling ReviveSatchel, so a wallet
## reset never strips carried items (Daniel, 2026-11-07).

signal balance_changed(new_balance: int)

var _balance := 0

func _ready() -> void:
	add_to_group("currency_wallet")

func balance() -> int:
	return _balance

func add(amount: int) -> void:
	if amount <= 0:
		return
	_balance += amount
	balance_changed.emit(_balance)

## Spends only when the full amount is affordable; otherwise changes nothing
## and returns false. The wallet never goes negative.
func try_spend(amount: int) -> bool:
	if amount <= 0 or amount > _balance:
		return false
	_balance -= amount
	balance_changed.emit(_balance)
	return true
