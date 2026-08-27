class_name WalletComponent
extends FrameworkComponent
## What an entity can pay with.
##
## Balances per currency, keyed by currency id rather than by definition
## reference, so a wallet's save record is a list of names and a currency can
## be moved on disk without invalidating every wallet in the game (rule 32).
##
## [b]Every mutation returns a result.[/b] Spending more than you have is a
## domain failure with a reason, not a silently clamped subtraction -- which is
## what rule 17 asks for and what makes a purchase reversible before it starts.

signal balance_changed(currency: StringName, balance: float, previous: float)
## Emitted when a withdrawal was refused for want of funds, so a UI can say so
## without re-deriving why.
signal payment_refused(currency: StringName, amount: float, balance: float)

## Starting balances. Parallel arrays rather than a dictionary because Godot
## exports those and not typed dictionaries of resources.
@export var starting_currencies: Array[StringName] = []

@export var starting_amounts: Array[float] = []

## Currency definitions this wallet knows the precision of. Resolved from the
## core's registry when not listed, and falling back to whole numbers when
## there is no registry at all (rule 31).
@export var currencies: Array[CurrencyDefinition] = []

var _balances: Dictionary[StringName, float] = {}
var _definitions: Dictionary[StringName, CurrencyDefinition] = {}
var _seeded: bool = false


func initialize(context: EntityContext) -> void:
	super(context)
	for definition in currencies:
		if definition != null and definition.id != &"":
			_definitions[definition.id] = definition
	_resolve_from_definition()
	if not _seeded:
		_seed()
		_seeded = true


# --- Queries --------------------------------------------------------------

func get_balance(currency: StringName) -> float:
	return _balances.get(currency, 0.0)


func has_currency(currency: StringName) -> bool:
	return _balances.has(currency)


func get_currencies() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_balances.keys())
	return ids


func can_afford(currency: StringName, amount: float) -> bool:
	if amount <= 0.0:
		return true
	var definition := get_currency(currency)
	if definition != null and definition.allows_debt:
		return true
	return get_balance(currency) >= _quantise(currency, amount)


## The currency's definition, when this wallet knows it. Null means precision
## falls back to whole numbers, which is the right default and never an error.
func get_currency(currency: StringName) -> CurrencyDefinition:
	if _definitions.has(currency):
		return _definitions[currency]
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_definition"):
		return null
	var found := core.call("get_definition", currency) as CurrencyDefinition
	if found != null:
		_definitions[currency] = found
	return found


## Player-facing balance: "250 g".
func format(currency: StringName) -> String:
	var definition := get_currency(currency)
	if definition == null:
		return String.num(get_balance(currency), 0)
	return definition.format(get_balance(currency))


# --- Mutating -------------------------------------------------------------

func deposit(currency: StringName, amount: float) -> FrameworkResult:
	if currency == &"":
		return FrameworkResult.fail(&"wallet.no_currency", "No currency named.")
	if amount <= 0.0:
		return FrameworkResult.fail(
			&"wallet.invalid_amount", "A deposit must be positive."
		)
	_apply_balance(currency, get_balance(currency) + _quantise(currency, amount))
	return FrameworkResult.ok(get_balance(currency))


## Takes money out, or refuses. Never partial: a purchase that took what it
## could and left the player short of the thing they bought would be worse
## than one that did not happen (rule 17).
func withdraw(currency: StringName, amount: float) -> FrameworkResult:
	if currency == &"":
		return FrameworkResult.fail(&"wallet.no_currency", "No currency named.")
	if amount <= 0.0:
		return FrameworkResult.fail(
			&"wallet.invalid_amount", "A withdrawal must be positive."
		)
	if not can_afford(currency, amount):
		payment_refused.emit(currency, amount, get_balance(currency))
		return FrameworkResult.fail(
			&"wallet.insufficient_funds",
			"Not enough %s: %s needed, %s held." % [
				currency, String.num(amount, 2), String.num(get_balance(currency), 2)
			]
		)
	_apply_balance(currency, get_balance(currency) - _quantise(currency, amount))
	return FrameworkResult.ok(get_balance(currency))


## Moves money to another wallet, or does neither. The two-sided version of
## the same atomicity: the withdrawal is checked before either side moves.
func transfer_to(
	other: WalletComponent, currency: StringName, amount: float
) -> FrameworkResult:
	if other == null:
		return FrameworkResult.fail(&"wallet.no_recipient", "There is nobody to pay.")
	if other == self:
		return FrameworkResult.fail(
			&"wallet.self_transfer", "A wallet cannot pay itself."
		)
	var taken := withdraw(currency, amount)
	if taken.is_err():
		return taken
	var given := other.deposit(currency, amount)
	if given.is_err():
		# Put it back. The recipient refusing is not a reason to destroy money.
		deposit(currency, amount)
		return given
	return FrameworkResult.ok(amount)


## Sets a balance outright. For a debug command and for a save restore, not
## for gameplay -- gameplay uses deposit and withdraw so a refusal has a
## reason.
func set_balance(currency: StringName, amount: float) -> void:
	if currency != &"":
		_apply_balance(currency, amount)


func clear() -> void:
	for currency in get_currencies():
		_apply_balance(currency, 0.0)


# --- Discovery ------------------------------------------------------------

static func find_on(node: Node) -> WalletComponent:
	if node == null:
		return null
	if node is WalletComponent:
		return node as WalletComponent
	for component in DefinitionBinder.collect_components(node):
		if component is WalletComponent:
			return component as WalletComponent
	return null


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	var saved: Dictionary = {}
	for currency in _balances:
		saved[String(currency)] = _balances[currency]
	return {"balances": saved}


func restore_state(data: Dictionary) -> void:
	_balances.clear()
	for key in data.get("balances", {}):
		_balances[StringName(key)] = float(data["balances"][key])
	# A restored wallet must not be topped up with starting money on the next
	# initialize, which is how a save reload turns into free gold.
	_seeded = true


# --- Internals ------------------------------------------------------------

## Named _apply_balance rather than _set: Object._set(property, value) is a
## Godot virtual, and shadowing it with a different signature is a parse
## error rather than an override.
func _apply_balance(currency: StringName, amount: float) -> void:
	var definition := get_currency(currency)
	var value := definition.clamp_balance(amount) if definition != null else roundf(
		maxf(0.0, amount)
	)
	var previous := get_balance(currency)
	if is_equal_approx(previous, value) and _balances.has(currency):
		return
	_balances[currency] = value
	balance_changed.emit(currency, value, previous)


func _quantise(currency: StringName, amount: float) -> float:
	var definition := get_currency(currency)
	return definition.quantise(amount) if definition != null else roundf(amount)


func _seed() -> void:
	var count := mini(starting_currencies.size(), starting_amounts.size())
	for index in count:
		_apply_balance(starting_currencies[index], starting_amounts[index])


## Read by property name rather than by casting, so a vehicle or a terminal
## with its own definition type can hold money (rule 9).
func _resolve_from_definition() -> void:
	var definition := get_definition()
	if definition == null or not "currencies" in definition:
		return
	var candidate: Variant = definition.get("currencies")
	if not candidate is Array:
		return
	for entry in candidate as Array:
		if entry is CurrencyDefinition and (entry as CurrencyDefinition).id != &"":
			_definitions[(entry as CurrencyDefinition).id] = entry
