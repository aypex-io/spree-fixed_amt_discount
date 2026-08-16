# Spree::FixedAmtDiscount

Spree's built-in `FlatRate` calculator doesn't handle fixed-amount discounts
well once tax is involved. Attached to a *per-line-item* promotion adjustment,
it applies the full amount to **every** line item — a £10 promo on a
three-item basket discounts £30, not £10. Attached to a *whole-order*
adjustment instead, it lands as a single order-level adjustment that can't be
apportioned between tax categories, so a VAT-inclusive store ends up with the
wrong tax breakdown. This gem adds a calculator that spreads one fixed amount
across the basket's line items in proportion to their value, so each item's
share — and its tax — comes out correct.

## Installation

Requires Spree >= 5.6.

```bash
bundle add spree-fixed_amt_discount
```

## Usage

In the Spree admin: **Promotion → Actions → Create per-line-item adjustment**,
then choose the **Fixed Amount (spread across line items)** calculator and set
its amount and currency.

## Behaviour

- The discount is split across actionable line items weighted by
  `price × quantity`, calculated **before** any discounts are applied — so
  when this promotion stacks with another one, the split is still based on
  each item's original price, not its already-discounted price.
- Because the split is proportional, the shares are rounded to the currency's
  minor unit and won't always sum exactly to the target amount. The last item
  (ordered by `id`) absorbs whatever rounding remainder is left, so the shares
  always sum to the full discount.
- If the discount amount is larger than the actionable total, it clamps to
  that total — the order can be discounted to zero but never goes negative.
- Line items excluded by the promotion's rules (e.g. per-item rules or
  promotion-category restrictions) are left out of the split entirely. Their
  value isn't counted in the denominator, so they don't dilute the discount
  shared among the remaining eligible items.

## Example

A £10 discount across three line items worth £33.33, £33.33 and £33.34 splits
as £3.33 / £3.33 / £3.34 — the third item picks up the extra penny so the
shares sum to exactly £10.00.

## Preferences

| Preference | Type | Default | Description |
|---|---|---|---|
| `amount` | decimal | — | The fixed amount to discount, before it's spread across line items. |
| `currency` | string | the default store's currency | The currency the amount is denominated in. |
| `apply_only_on_full_priced_items` | boolean | `false` | When `true`, excludes items with a compare-at price from both the split's numerator and its denominator. |

## Development

```bash
bundle install
bundle exec rake test_app
bundle exec rspec
```

## Licence

The gem is available as open source under the terms of the [MIT
Licence](LICENSE).
