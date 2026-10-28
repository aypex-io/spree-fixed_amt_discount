# frozen_string_literal: true

require_dependency "spree/calculator"

module Spree
  ##
  # Spreads a single fixed discount amount across the actionable line items in
  # proportion to their value, so each item carries its own share and Spree
  # recalculates per-item tax against it.
  #
  class Calculator::FixedAmountOnLineItems < Calculator
    preference :amount, :decimal, default: 0
    preference :currency, :string, default: -> { Spree::Store.default&.default_currency }
    preference :apply_only_on_full_priced_items, :boolean, default: false

    ##
    # Translated label shown in the Spree dashboard calculator picker.
    #
    # @return [String]
    #
    def self.description
      I18n.t("spree.fixed_amount_on_line_items")
    end

    ##
    # Returns this line item's non-negative share of the fixed amount.
    #
    # +Spree::Promotion::Actions::CreateItemAdjustments+ negates the result and
    # applies its own guard against a negative order total.
    #
    # @param line_item [Spree::LineItem, NilClass] the item to compute a share for
    # @return [BigDecimal, Integer] non-negative share in the item's currency
    #
    def compute(line_item = nil)
      return 0 unless applicable?(line_item)

      # A line item belongs to a cart during checkout and to an order once
      # placed; `owner` is whichever it has.
      items = actionable_line_items(line_item.owner)
      return 0 unless items.include?(line_item)

      total = items.sum(&:amount)
      return 0 unless total.positive?

      # Guard against a negative remainder becoming a positive (surcharge)
      # adjustment once Spree core negates it, and never exceed the item's own
      # amount.
      share_for(line_item, items, total).clamp(0, line_item.amount)
    end

    private

    def applicable?(line_item)
      return false if line_item.nil?

      preferred_currency.to_s.casecmp(line_item.currency.to_s).zero?
    end

    # Clamp: a fixed amount larger than the basket discounts it to zero, never
    # below. Matches Spree::Calculator::PercentOnLineItem. Rounded to the
    # currency's minor unit (2 places for most, 0 for yen) so a finer
    # preferred_amount can't leave the last item's remainder off-currency;
    # Spree refuses a discount with more decimals than its currency has.
    # The last item absorbs the rounding remainder so the shares sum to (at
    # most) the budget rather than drifting by a penny or two.
    def share_for(line_item, items, total)
      budget = Spree::Money::Rounding.to_currency([preferred_amount, total].min, line_item.currency)
      return pro_rata(line_item, budget, total) unless line_item == items.last

      budget - items[0..-2].sum { |item| pro_rata(item, budget, total) }
    end

    def pro_rata(item, budget, total)
      # Round down, not to nearest: rounding earlier shares up can push their
      # sum past the budget, forcing the last item's remainder negative --
      # which core would then negate into a positive surcharge on that line
      # item. Rounding down (the same as flooring, since shares are never
      # negative) guarantees the running sum never exceeds the budget, so the
      # remainder is provably non-negative (at worst it's a small shortfall).
      Spree::Money::Rounding.to_currency(budget * item.amount / total, item.currency, mode: :down)
    end

    def actionable_line_items(order)
      return [] if order.nil?

      # Sorted by id so "the last item" -- the one absorbing the remainder --
      # is the same on every call. Core only computes against persisted line
      # items; the to_i keeps an unsaved one from raising on comparison.
      order.line_items.to_a
        .select { |item| actionable?(order, item) }
        .sort_by { |item| item.id.to_i }
    end

    # Excluded items must leave the actionable set entirely -- dropping them
    # from the numerator alone would dilute the remaining items' shares and
    # apply less than the promised amount.
    def actionable?(order, item)
      return false if preferred_apply_only_on_full_priced_items && on_sale?(item)
      return true if promotion.nil?

      promotion.line_item_actionable?(order, item)
    end

    def on_sale?(item)
      item.variant&.compare_at_amount_in(item.currency).present?
    end

    # `calculable` is the Spree::Promotion::Actions::CreateItemAdjustments this
    # calculator belongs to. A bare calculator (no action) has none.
    def promotion
      calculable.try(:promotion)
    end
  end
end
