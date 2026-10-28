# frozen_string_literal: true

require "spec_helper"

# Promotions are applied to carts during checkout, and a cart's line items
# have no order. Items go in through Spree::Carts::AddItem, the path the
# storefront uses, which recalculates the cart and applies automatic
# promotions to it.
RSpec.describe("fixed amount promotion applied across a cart's line items") do
  let(:store) { Spree::Store.default }
  let(:cart) { create(:cart, store: store, currency: "USD") }

  let!(:promotion) do
    promo = create(:promotion, kind: :automatic, store: store, name: "Tenner off")
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 10,
        preferred_currency: "USD"
      )
    )
    promo
  end

  def add_items(*prices)
    prices.each do |price|
      result = Spree::Carts::AddItem.call(cart: cart, variant: create(:variant, price: price), quantity: 1)
      expect(result).to be_success
    end
    cart.reload
  end

  def discounts
    cart.line_items.flat_map(&:promotion_discounts)
  end

  it("creates one discount per line item") do
    add_items(33.33, 33.33, 33.34)

    expect(cart.line_items.map { |item| item.promotion_discounts.count }).to eq([1, 1, 1])
  end

  it("discounts the cart by exactly the fixed amount") do
    add_items(33.33, 33.33, 33.34)

    expect(discounts.sum(&:amount)).to eq(BigDecimal("-10"))
  end

  it("reduces the cart total by exactly the fixed amount") do
    add_items(50, 50)

    expect(cart.total).to eq(BigDecimal(90))
  end

  context "when the amount exceeds the basket" do
    before { promotion.actions.first.calculator.update!(preferred_amount: 500) }

    it("does not drive the cart total negative") do
      add_items(20, 10)

      expect(cart.total).to be >= 0
    end

    it("clamps the discount to the basket total") do
      add_items(20, 10)

      expect(discounts.sum(&:amount)).to eq(BigDecimal("-30"))
    end
  end
end
