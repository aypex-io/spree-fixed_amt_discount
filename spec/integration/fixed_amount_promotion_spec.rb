require 'spec_helper'

RSpec.describe 'fixed amount promotion applied across line items' do
  let(:store) { Spree::Store.default }

  let(:promotion) do
    promo = create(:promotion, store: store, name: 'Tenner off')
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 10,
        preferred_currency: 'USD'
      )
    )
    promo
  end

  def order_with_amounts(*amounts)
    order = create(:order, store: store, currency: 'USD')
    amounts.each do |item_amount|
      create(:line_item, order: order, price: item_amount, quantity: 1, currency: 'USD')
    end
    order.reload
  end

  def apply(order)
    promotion.actions.each { |action| action.perform(order: order, promotion: promotion) }
    order.reload
    order.update_with_updater!
    order.reload
  end

  it 'creates one adjustment per line item' do
    order = order_with_amounts(33.33, 33.33, 33.34)

    apply(order)

    expect(order.line_items.map { |item| item.adjustments.count }).to eq([1, 1, 1])
  end

  it 'discounts the order by exactly the fixed amount' do
    order = order_with_amounts(33.33, 33.33, 33.34)

    apply(order)

    expect(order.line_items.flat_map(&:adjustments).sum(&:amount)).to eq(BigDecimal('-10'))
  end

  it 'reduces the order item total by exactly the fixed amount' do
    order = order_with_amounts(50, 50)

    apply(order)

    expect(order.item_total + order.line_items.flat_map(&:adjustments).sum(&:amount)).
      to eq(BigDecimal('90'))
  end

  it 'does not drive the order total negative when the amount exceeds the basket' do
    promotion.actions.first.calculator.update!(preferred_amount: 500)
    order = order_with_amounts(20, 10)

    apply(order)

    expect(order.total).to be >= 0
  end
end
