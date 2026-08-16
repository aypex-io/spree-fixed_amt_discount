require 'spec_helper'

RSpec.describe 'fixed amount promotion and VAT inclusive tax' do
  let(:store) { Spree::Store.default }
  let(:zone) { create(:global_zone) }

  let(:standard_category) { create(:tax_category, name: 'Standard') }
  let(:reduced_category)  { create(:tax_category, name: 'Reduced') }

  let!(:standard_rate) do
    create(:tax_rate,
           zone: zone,
           tax_category: standard_category,
           amount: 0.20,
           included_in_price: true)
  end

  let!(:reduced_rate) do
    create(:tax_rate,
           zone: zone,
           tax_category: reduced_category,
           amount: 0.05,
           included_in_price: true)
  end

  let(:standard_product) { create(:product, price: 60, tax_category: standard_category) }
  let(:reduced_product)  { create(:product, price: 60, tax_category: reduced_category) }

  let(:promotion) do
    promo = create(:promotion, store: store, name: 'Twelve off')
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 12,
        preferred_currency: 'USD'
      )
    )
    promo
  end

  let(:order) do
    order = create(:order_with_line_items,
                   store: store,
                   currency: 'USD',
                   line_items_count: 0,
                   ship_address: create(:address))
    create(:line_item, order: order, variant: standard_product.master, price: 60, quantity: 1, currency: 'USD')
    create(:line_item, order: order, variant: reduced_product.master, price: 60, quantity: 1, currency: 'USD')
    order.reload
  end

  before do
    promotion.actions.each { |action| action.perform(order: order, promotion: promotion) }
    order.reload
    order.update_with_updater!
    order.reload
  end

  def line_item_for(product)
    order.line_items.detect { |item| item.variant_id == product.master.id }
  end

  it 'splits the discount evenly across the two items' do
    expect(order.line_items.flat_map(&:adjustments).select(&:promotion?).sum(&:amount)).
      to eq(BigDecimal('-12'))
  end

  it 'recalculates the standard rated item tax against its discounted amount' do
    # 54.00 * 20 / 120
    expect(line_item_for(standard_product).included_tax_total).to eq(BigDecimal('9.00'))
  end

  it 'recalculates the reduced rated item tax against its discounted amount' do
    # 54.00 * 5 / 105, rounded
    expect(line_item_for(reduced_product).included_tax_total).to eq(BigDecimal('2.57'))
  end

  it 'produces a per-category tax total an order level adjustment could not' do
    expect(order.included_tax_total).to eq(BigDecimal('11.57'))
  end
end
