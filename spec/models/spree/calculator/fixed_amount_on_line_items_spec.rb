require 'spec_helper'

RSpec.describe Spree::Calculator::FixedAmountOnLineItems do
  subject(:calculator) { described_class.new(preferred_amount: amount, preferred_currency: 'USD') }

  let(:amount) { 10 }
  let(:store) { Spree::Store.default }

  # Builds a persisted order whose line items have exactly the given amounts.
  def order_with_amounts(*amounts)
    order = create(:order, store: store, currency: 'USD')
    amounts.each do |item_amount|
      create(:line_item, order: order, price: item_amount, quantity: 1, currency: 'USD')
    end
    order.reload
  end

  def shares(order)
    order.line_items.sort_by(&:id).map { |item| calculator.compute(item) }
  end

  describe '#compute' do
    it 'splits evenly across equal line items' do
      order = order_with_amounts(50, 50)

      expect(shares(order)).to eq([BigDecimal('5'), BigDecimal('5')])
    end

    it 'gives a single line item the whole amount' do
      order = order_with_amounts(50)

      expect(shares(order)).to eq([BigDecimal('10')])
    end

    it 'weights the split by line item value' do
      order = order_with_amounts(75, 25)

      expect(shares(order)).to eq([BigDecimal('7.5'), BigDecimal('2.5')])
    end

    it 'reconciles rounding pennies so the shares sum to exactly the amount' do
      order = order_with_amounts(33.33, 33.33, 33.34)

      result = shares(order)

      expect(result.sum).to eq(BigDecimal('10'))
      expect(result).to eq([BigDecimal('3.33'), BigDecimal('3.33'), BigDecimal('3.34')])
    end

    it 'returns amounts rounded to two decimal places' do
      order = order_with_amounts(10, 20, 70)

      shares(order).each do |share|
        expect(share).to eq(share.round(2))
      end
    end

    it 'returns 0 when there are no line items' do
      order = create(:order, store: store, currency: 'USD')
      line_item = build(:line_item, order: order, price: 10, quantity: 1)

      expect(calculator.compute(line_item)).to eq(0)
    end

    it 'returns 0 when given nil' do
      expect(calculator.compute(nil)).to eq(0)
    end
  end

  describe '.description' do
    it 'is translated' do
      expect(described_class.description).to eq('Fixed Amount (spread across line items)')
    end
  end
end
