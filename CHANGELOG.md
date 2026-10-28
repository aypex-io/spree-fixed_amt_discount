# Changelog

## 0.2.0

- Requires Spree 6 (`~> 6.0`). Spree 5.6 stores should stay on 0.1.x.
- Fix: the discount came out as zero during checkout on Spree 6, where a
  cart's line items have no order. The calculator now reads the line item's
  owner (its cart or its order).
- Rounds each share to the currency's own minor unit (for example whole yen)
  instead of always two decimal places; Spree 6 refuses a discount with more
  decimals than its currency has.
- No longer raises when there is no default store (`Store.default` can be nil
  on Spree 6).
- Uses `I18n.t` instead of the deprecated `Spree.t`.

## 0.1.0

- Initial release.
- Adds `Spree::Calculator::FixedAmountOnLineItems`, a promotion calculator that
  spreads a single fixed discount amount across the actionable line items in
  proportion to their value, so per-item tax is recalculated correctly.
- Registered automatically for per-line-item promotion adjustments.
- Requires Spree >= 5.6.
