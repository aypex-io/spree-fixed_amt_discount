# spree-fixed_amt_discount — design

Date: 2026-08-16
Status: approved, ready for implementation planning

## Problem

Spree ships two ways to express "£10 off":

- `Spree::Calculator::FlatRate` on a **whole-order** adjustment
  (`CreateAdjustment`). One adjustment lands on the order, unattached to any
  line item. Per-line-item tax cannot be recalculated from it, so on a
  VAT-inclusive store the tax breakdown is wrong whenever the basket mixes tax
  categories or rates.
- `Spree::Calculator::FlatRate` on a **per-line-item** adjustment
  (`CreateItemAdjustments`). Core calls `compute(line_item)` once per line item
  and `FlatRate` returns its full preferred amount every time — so a £10 promo
  on a three-item basket discounts £30.

There is no calculator that spreads a single fixed amount across the actionable
line items. That is the gap this gem fills: a whole-order-feeling fixed discount
that is physically applied per line item, so Spree's existing tax machinery
recalculates each item's tax correctly.

Prior art: `MatthewKennedy/spree_fixed_amt_discount` (private, Spree 3.7–4.2).
The pro-rata maths is sound and is ported. Its delivery mechanism is not — see
"Rejected approaches".

## Scope

In scope: one promotion calculator, its registration, tests, CI, and a RubyGems
release.

Out of scope: any other discount or VAT correctness work in Spree. Whole-order
adjustment behaviour, promotions basing off `order.total` versus `item_total`,
and the promotion system generally are untouched. If a concrete bug is found
there it gets its own spec.

## Constraints

- Spree **>= 5.6** only. No back-compatibility shims, no Appraisals matrix.
  Targets the single-argument `compute(line_item)` calculator API directly.
- Ruby >= 3.3.
- No monkey-patching of Spree core classes. A Spree minor upgrade must not be
  able to break this gem silently.

## Approach

A single self-sufficient calculator, registered into Spree's existing
per-line-item calculator list. Nothing in core is decorated or replaced.

The calculator reaches the promotion through associations core already
provides:

```
calculator.calculable        # => the Spree::Promotion::Actions::CreateItemAdjustments
calculator.calculable.promotion  # => the Spree::Promotion
```

so it can determine the actionable line-item set itself, rather than needing
core to pass that context in.

### Rejected approaches

**Monkey-patch `CreateItemAdjustments` to pass extra arguments into `compute`**
(what the old gem did). Replaces a core class wholesale: it fights any other
extension decorating the same action, breaks silently if core changes the
method, and leaves the calculator unusable against an unpatched action. Also
forced the old gem to reimplement core's "don't push the order negative" guard.

**A dedicated `PromotionAction` subclass** holding the pro-rata logic. Arguably
a more natural home for the concern, but it puts a second near-identical action
in the admin dropdown that store admins must choose between, for one
calculator's worth of behaviour.

## Components

### `Spree::Calculator::FixedAmountOnLineItems`

`app/models/spree/calculator/fixed_amount_on_line_items.rb`

Named for consistency with core's `PercentOnLineItem` and
`FlatPercentItemTotal`. This string is persisted in `spree_calculators.type`,
so it is fixed at first release; there is no legacy data to migrate because
nothing has ever run the predecessor gem.

**Preferences**

| Preference | Type | Default | Purpose |
|---|---|---|---|
| `amount` | decimal | `0` | The fixed amount to spread across the actionable items. |
| `currency` | string | `Spree::Store.default.default_currency` | Matches Spree 5.6 `FlatRate`. |
| `apply_only_on_full_priced_items` | boolean | `false` | Parity with both sibling core calculators. |

**`compute(line_item)`** returns a non-negative `BigDecimal` — this line item's
share. Core's `compute_amount` negates it and applies its own caps.

1. Return `0` unless `preferred_currency` case-insensitively matches
   `line_item.currency`.
2. Build the actionable set from `line_item.order.line_items`:
   - keep those where `calculable.promotion.line_item_actionable?(order, li)`,
   - when `apply_only_on_full_priced_items`, drop items with a
     `compare_at_amount_in(currency)` present,
   - sort by `id` so "last item" is deterministic.
3. Return `0` if the set is empty, if its total is zero, or if `line_item` is
   not in it.
4. `budget = [preferred_amount, actionable_total].min`.
5. Share:
   - not the last item: `(budget * line_item.amount / actionable_total).round(2)`
   - the last item: `budget - (sum of every earlier item's share)`
6. Return `[share, line_item.amount].min`.

**Weighting.** The split weights by `line_item.amount` (`price * quantity`,
before discounts). This matches core's `PercentOnLineItem`, and Spree 5.6 has
no `LineItem#discounted_amount` to weight by instead. Consequence: when this
promo stacks with another, it still splits by original prices.

**Clamping.** When the fixed amount exceeds the actionable total, the discount
is clamped to that total — the order goes to zero, never negative. This matches
core's `PercentOnLineItem` and avoids a promo that silently does nothing. The
per-item `min` in step 6 can, in a contrived basket where the last item is
smaller than the accumulated rounding remainder, leave the applied total up to
one penny short of the budget. Accepted.

**Negative-total guard.** Not implemented here. Core's `compute_amount` already
subtracts existing eligible adjustments from the order amount and takes the
minimum. The old gem reimplemented this because its monkey-patch had replaced
it; approach 1 inherits it.

**Complexity.** The actionable set is rebuilt on each `compute` call, so
computing a whole order is O(n²) in line items. Irrelevant at realistic basket
sizes; not optimised.

### Engine registration

`lib/spree/fixed_amt_discount/engine.rb`

Appends the calculator inside the engine's **`config.after_initialize`**:

```ruby
config.after_initialize do
  Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments <<
    Spree::Calculator::FixedAmountOnLineItems
end
```

**This placement is load-bearing.** `spree_core`'s engine *assigns* that array
with `=` inside its own `config.after_initialize`. A `config/initializers/*.rb`
file — which is what the predecessor gem used — runs during engine
initialization, i.e. *before* `after_initialize`, and is therefore silently
clobbered. Our engine is initialized after `spree_core` (we depend on it), so
our `after_initialize` block is registered later and runs later. A spec asserts
the registration survives boot so this cannot regress unnoticed.

Once registered, the calculator appears automatically in the admin promotion
form's calculator dropdown under *Create per-line-item adjustment*. No admin
views are overridden. `config/locales/en.yml` supplies the label returned by
`self.description`.

## Testing

RSpec against a dummy app via `spree_dev_tools`, matching
`aypex-io/spree-bank_payments`.

**Calculator unit specs**

- even split across equal line items
- uneven split where pennies must reconcile — e.g. £10 across £33.33 / £33.33 /
  £33.34 — asserting the shares sum to exactly the fixed amount
- currency mismatch returns 0
- fixed amount exceeding the actionable total clamps to that total; order
  reaches zero and not below
- promotion rules excluding some items: excluded items get 0 **and** do not
  dilute the remaining items' shares (guards the denominator)
- single actionable line item takes the whole amount
- empty actionable set returns 0
- `apply_only_on_full_priced_items` excludes sale items from numerator and
  denominator

**Integration spec.** A real promotion and order; the resulting adjustments sum
to exactly the fixed amount.

**Tax spec.** The reason the gem exists. A VAT-inclusive tax rate over line
items in **different tax categories**, asserting each item's tax recalculates
against its discounted amount. Doubles as the regression test for the case
core's `FlatRate` gets wrong.

**Registration spec.** Asserts the calculator is present in
`Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments`
after boot.

## Packaging and release

Repository `aypex-io/spree-fixed_amt_discount`, public, MIT.

```
spree-fixed_amt_discount.gemspec
lib/spree-fixed_amt_discount.rb
lib/spree/fixed_amt_discount/version.rb
lib/spree/fixed_amt_discount/engine.rb
app/models/spree/calculator/fixed_amount_on_line_items.rb
config/locales/en.yml
spec/
```

Gemspec mirrors `spree-bank_payments`: author `Aypex`, `hello@aypex.io`,
`rubygems_mfa_required`, `spree_dev_tools` as a development dependency.

Runtime dependency is **`spree >= 5.6.0` only**. `spree-bank_payments` also
depends on `spree_admin` because it ships admin views; this gem ships none —
the calculator surfaces through a dropdown that `spree_admin` renders from
core's config array, so the host store owns that dependency, not us.

`ci.yml` and `release.yml` are copied from `spree-bank_payments`.

First release is **0.1.0**. Unlike `spree-bank_payments` there is no reason to
shadow Spree's version line.

The name `spree-fixed_amt_discount` was confirmed unclaimed on RubyGems on
2026-08-16.

## Order of work

1. Scaffold the gem (gemspec, lib layout, spec harness, CI).
2. Calculator plus unit specs, test-first.
3. Engine registration plus its registration spec.
4. Integration and tax specs.
5. README and CHANGELOG.
6. CI green.
7. Create the GitHub repo, tag, publish 0.1.0.
