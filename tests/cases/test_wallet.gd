extends FrameworkTestCase
## Covers CurrencyDefinition and WalletComponent.

var entity: Node = null
var wallet: WalletComponent = null


func before_each() -> void:
	entity = add_test_node(Node3D.new())
	wallet = CommerceFixtures.wallet(100.0)
	entity.add_child(wallet)
	CommerceFixtures.assemble(entity)


# --- Currency -------------------------------------------------------------

func test_a_whole_number_currency_rounds() -> void:
	var gold := CommerceFixtures.gold()
	assert_almost_eq(gold.quantise(12.7), 13.0)
	assert_eq(gold.format(250.0), "250 g")


func test_a_currency_with_decimals_keeps_them() -> void:
	var credits := CommerceFixtures.gold()
	credits.id = &"currency.credits"
	credits.symbol = "$"
	credits.symbol_leads = true
	credits.decimals = 2
	assert_almost_eq(credits.quantise(12.345), 12.35)
	assert_eq(credits.format(12.5), "$12.50")


func test_balances_are_clamped_at_zero_unless_debt_is_allowed() -> void:
	var gold := CommerceFixtures.gold()
	assert_almost_eq(gold.clamp_balance(-50.0), 0.0)
	gold.allows_debt = true
	assert_almost_eq(gold.clamp_balance(-50.0), -50.0)


func test_a_ceiling_caps_a_balance() -> void:
	var gold := CommerceFixtures.gold()
	gold.maximum = 999.0
	assert_almost_eq(gold.clamp_balance(5000.0), 999.0)


func test_a_currency_with_no_symbol_is_flagged() -> void:
	var plain := CommerceFixtures.gold()
	plain.symbol = ""
	assert_true(plain.validate().has_warnings())


# --- Balances -------------------------------------------------------------

func test_a_wallet_starts_with_what_it_was_given() -> void:
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 100.0)
	assert_true(wallet.has_currency(&"currency.gold"))


func test_an_unknown_currency_reads_as_zero() -> void:
	assert_almost_eq(wallet.get_balance(&"currency.nothing"), 0.0)


func test_depositing_and_withdrawing() -> void:
	assert_ok(wallet.deposit(&"currency.gold", 50.0))
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 150.0)
	assert_ok(wallet.withdraw(&"currency.gold", 25.0))
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 125.0)


func test_spending_more_than_you_have_is_refused_outright() -> void:
	# Never partial. A purchase that took what it could and left the player
	# short of the thing they bought would be worse than one that did not
	# happen (rule 17).
	assert_err(wallet.withdraw(&"currency.gold", 500.0), &"wallet.insufficient_funds")
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 100.0)


func test_a_refusal_is_announced_with_the_shortfall() -> void:
	var refusals: Array[float] = []
	wallet.payment_refused.connect(
		func(_c: StringName, amount: float, _b: float) -> void: refusals.append(amount)
	)
	wallet.withdraw(&"currency.gold", 500.0)
	assert_size(refusals, 1)
	assert_almost_eq(refusals[0], 500.0)


func test_balance_changes_are_announced() -> void:
	var changes: Array[float] = []
	wallet.balance_changed.connect(
		func(_c: StringName, balance: float, _p: float) -> void: changes.append(balance)
	)
	wallet.deposit(&"currency.gold", 10.0)
	wallet.deposit(&"currency.gold", 0.0)
	assert_size(changes, 1)


func test_negative_and_zero_amounts_are_refused() -> void:
	assert_err(wallet.deposit(&"currency.gold", -5.0), &"wallet.invalid_amount")
	assert_err(wallet.withdraw(&"currency.gold", 0.0), &"wallet.invalid_amount")


func test_a_debt_currency_can_go_negative() -> void:
	var debt := CommerceFixtures.gold()
	debt.id = &"currency.favours"
	debt.allows_debt = true

	var borrower := add_test_node(Node3D.new())
	var purse := CommerceFixtures.wallet(0.0, debt)
	borrower.add_child(purse)
	CommerceFixtures.assemble(borrower)

	assert_true(purse.can_afford(&"currency.favours", 50.0))
	assert_ok(purse.withdraw(&"currency.favours", 50.0))
	assert_almost_eq(purse.get_balance(&"currency.favours"), -50.0)


func test_amounts_are_quantised_to_the_currency() -> void:
	# A wallet drifting into fractions of a currency that has none is the bug
	# that shows up as a shop refusing a purchase the player can afford.
	wallet.deposit(&"currency.gold", 0.4)
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 100.0)


func test_a_wallet_formats_its_own_balance() -> void:
	assert_eq(wallet.format(&"currency.gold"), "100 g")


# --- Transfers ------------------------------------------------------------

func _second_wallet(balance: float = 0.0) -> WalletComponent:
	var other := add_test_node(Node3D.new())
	var purse := CommerceFixtures.wallet(balance)
	other.add_child(purse)
	CommerceFixtures.assemble(other)
	return purse


func test_a_transfer_moves_money_both_ways() -> void:
	var other := _second_wallet()
	assert_ok(wallet.transfer_to(other, &"currency.gold", 40.0))
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 60.0)
	assert_almost_eq(other.get_balance(&"currency.gold"), 40.0)


func test_a_transfer_that_cannot_be_afforded_moves_nothing() -> void:
	var other := _second_wallet()
	assert_err(
		wallet.transfer_to(other, &"currency.gold", 500.0), &"wallet.insufficient_funds"
	)
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 100.0)
	assert_almost_eq(other.get_balance(&"currency.gold"), 0.0)


func test_a_transfer_to_nobody_is_refused() -> void:
	assert_err(wallet.transfer_to(null, &"currency.gold", 10.0), &"wallet.no_recipient")
	assert_err(wallet.transfer_to(wallet, &"currency.gold", 10.0), &"wallet.self_transfer")


func test_a_recipient_that_cannot_accept_gets_the_money_put_back() -> void:
	# The recipient refusing is not a reason to destroy money.
	var capped := CommerceFixtures.gold()
	capped.id = &"currency.gold"
	capped.maximum = 10.0
	var other := add_test_node(Node3D.new())
	var purse := CommerceFixtures.wallet(10.0, capped)
	other.add_child(purse)
	CommerceFixtures.assemble(other)

	wallet.transfer_to(purse, &"currency.gold", 50.0)
	assert_almost_eq(
		wallet.get_balance(&"currency.gold") + purse.get_balance(&"currency.gold"),
		60.0,
		0.01,
		"money is conserved even when the recipient is capped"
	)


# --- Persistence ----------------------------------------------------------

func test_balances_survive_a_save() -> void:
	wallet.deposit(&"currency.gold", 250.0)
	var saved := wallet.capture_state()
	wallet.clear()
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 0.0)

	wallet.restore_state(saved)
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 350.0)


func test_a_restored_wallet_is_not_topped_up_again() -> void:
	# Otherwise every save reload is free gold.
	wallet.restore_state({"balances": {"currency.gold": 5.0}})
	wallet.initialize(EntityContext.create(entity))
	assert_almost_eq(wallet.get_balance(&"currency.gold"), 5.0)


func test_wallets_are_persistent() -> void:
	assert_true(wallet.is_persistent())


func test_find_on_locates_a_wallet() -> void:
	assert_eq(WalletComponent.find_on(entity), wallet)
	assert_null(WalletComponent.find_on(add_test_node(Node.new())))
