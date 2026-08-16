require_dependency 'spree/calculator'

module Spree
  # Spreads a single fixed discount amount across the actionable line items in
  # proportion to their value, so each item carries its own share and Spree
  # recalculates per-item tax against it.
  class Calculator::FixedAmountOnLineItems < Calculator
    preference :amount, :decimal, default: 0
    preference :currency, :string, default: -> { Spree::Store.default.default_currency }
    preference :apply_only_on_full_priced_items, :boolean, default: false

    def self.description
      Spree.t(:fixed_amount_on_line_items)
    end

    # Returns this line item's non-negative share of the fixed amount.
    # Spree::Promotion::Actions::CreateItemAdjustments negates the result and
    # applies its own guard against a negative order total.
    def compute(line_item = nil)
      return 0 if line_item.nil?
      return 0 unless preferred_currency.to_s.casecmp(line_item.currency.to_s).zero?

      items = actionable_line_items(line_item.order)
      return 0 unless items.include?(line_item)

      total = items.sum(&:amount)
      return 0 unless total.positive?

      budget = preferred_amount

      if line_item == items.last
        # The last item absorbs the rounding remainder so the shares sum to
        # exactly the budget rather than drifting by a penny or two.
        budget - items[0..-2].sum { |item| pro_rata(item, budget, total) }
      else
        pro_rata(line_item, budget, total)
      end
    end

    private

    def pro_rata(item, budget, total)
      (budget * item.amount / total).round(2)
    end

    def actionable_line_items(order)
      return [] if order.nil?

      # Sorted by id so "the last item" -- the one absorbing the remainder --
      # is the same on every call. Core only computes against persisted line
      # items; the to_i keeps an unsaved one from raising on comparison.
      order.line_items.to_a.sort_by { |item| item.id.to_i }
    end
  end
end
