# frozen_string_literal: true

require "spec_helper"

# Spree 6 decides whether prices include tax per market (`tax_inclusive`);
# tax rates are per country and no longer say it themselves.
RSpec.describe("fixed amount promotion with VAT inclusive tax") do
  let(:store) { Spree::Store.default }
  let(:cart) { create(:cart, store: store, currency: "USD") }

  let(:standard_category) { create(:tax_category, name: "Standard") }
  let(:reduced_category) { create(:tax_category, name: "Reduced") }

  let!(:standard_rate) do
    create(:tax_rate, country_code: @default_country&.iso, tax_category: standard_category, amount: 0.20)
  end

  let!(:reduced_rate) do
    create(:tax_rate, country_code: @default_country&.iso, tax_category: reduced_category, amount: 0.05)
  end

  let(:standard_product) { create(:product, price: 60, tax_category: standard_category, store: store) }
  let(:reduced_product) { create(:product, price: 60, tax_category: reduced_category, store: store) }

  let!(:promotion) do
    promo = create(:promotion, kind: :automatic, store: store, name: "Twelve off")
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 12,
        preferred_currency: "USD"
      )
    )
    promo
  end

  before do
    cart.market.update!(tax_inclusive: true)
    [standard_product, reduced_product].each do |product|
      expect(Spree::Carts::AddItem.call(cart: cart, variant: product.default_variant, quantity: 1)).to be_success
    end
    cart.reload
  end

  def line_item_for(product)
    cart.line_items.detect { |item| item.variant_id == product.default_variant.id }
  end

  it("splits the discount evenly across the two items") do
    expect(cart.line_items.flat_map(&:promotion_discounts).sum(&:amount)).to eq(BigDecimal("-12"))
  end

  it("recalculates the standard rated item tax against its discounted amount") do
    # 54.00 * 20 / 120
    expect(line_item_for(standard_product).included_tax_total).to eq(BigDecimal("9.00"))
  end

  it("recalculates the reduced rated item tax against its discounted amount") do
    # 54.00 * 5 / 105, rounded
    expect(line_item_for(reduced_product).included_tax_total).to eq(BigDecimal("2.57"))
  end

  it("produces a per-category tax total an order level adjustment could not") do
    expect(cart.included_tax_total).to eq(BigDecimal("11.57"))
  end
end
