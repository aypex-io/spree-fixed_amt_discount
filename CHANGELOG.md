# Changelog

## 0.1.0

- Initial release.
- Adds `Spree::Calculator::FixedAmountOnLineItems`, a promotion calculator that
  spreads a single fixed discount amount across the actionable line items in
  proportion to their value, so per-item tax is recalculated correctly.
- Registered automatically for per-line-item promotion adjustments.
- Requires Spree >= 5.6.
