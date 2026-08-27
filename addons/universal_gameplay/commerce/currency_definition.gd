class_name CurrencyDefinition
extends FrameworkDefinition
## A kind of money: gold, credits, scrip, favours.
##
## Separate from [ItemDefinition] on purpose. Coins that live in the bag and
## take up slots are items and should be; a balance is a number on an entity,
## and modelling a thousand credits as a thousand stacked objects is how an
## inventory ends up sorting a bank account.
##
## A project that wants physical coins simply uses an item instead, and
## nothing here objects.

## Shown next to an amount: "g", "cr", "$". Kept apart from
## [member display_name] because one is prose and the other is a glyph.
@export var symbol: String = ""

## Whether the symbol goes before the number. False for "100 g", true for
## "$100".
@export var symbol_leads: bool = false

## Decimal places tracked. Zero is the usual case: a currency with fractions
## makes every price comparison a rounding argument.
@export_range(0, 4) var decimals: int = 0

## Most balances cannot go below zero. A debt currency can.
@export var allows_debt: bool = false

## Ceiling on a balance. Zero means none.
@export_range(0.0, 999999999.0, 1.0, "or_greater") var maximum: float = 0.0


## Rounds [param amount] to this currency's precision.
##
## Every mutation goes through this, so a wallet cannot drift into fractions
## of a currency that has none -- which is the bug that shows up as a shop
## refusing a purchase the player can visibly afford.
func quantise(amount: float) -> float:
	if decimals <= 0:
		return roundf(amount)
	var factor := pow(10.0, decimals)
	return roundf(amount * factor) / factor


## What a balance is allowed to be, after clamping.
func clamp_balance(amount: float) -> float:
	var value := quantise(amount)
	if not allows_debt:
		value = maxf(0.0, value)
	if maximum > 0.0:
		value = minf(maximum, value)
	return value


## Player-facing amount: "250 g", "$12.50".
func format(amount: float) -> String:
	# pad_decimals because String.num trims trailing zeros, and a price of
	# "$12.5" is the kind of thing every project fixes once. A currency with
	# no decimals pads to none and is unaffected.
	var text := String.num(quantise(amount), decimals).pad_decimals(decimals)
	if symbol.is_empty():
		return text
	return "%s%s" % [symbol, text] if symbol_leads else "%s %s" % [text, symbol]


func validate() -> ValidationResult:
	var result := super()
	if symbol.is_empty():
		result.add_warning(
			&"currency.no_symbol",
			"%s has no symbol, so amounts will show as bare numbers." % get_debug_name(),
			resource_path,
			"symbol"
		)
	if maximum > 0.0 and allows_debt and maximum <= 0.0:
		result.add_warning(
			&"currency.debt_with_ceiling",
			"%s allows debt but has a ceiling at or below zero." % get_debug_name(),
			resource_path,
			"maximum"
		)
	return result
