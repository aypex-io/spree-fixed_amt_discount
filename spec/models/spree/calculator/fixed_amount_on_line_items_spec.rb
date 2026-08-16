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

    context 'when the currency does not match' do
      subject(:calculator) { described_class.new(preferred_amount: 10, preferred_currency: 'GBP') }

      it 'returns 0' do
        order = order_with_amounts(50, 50)

        expect(shares(order)).to eq([0, 0])
      end
    end

    context 'when the currency matches in a different case' do
      subject(:calculator) { described_class.new(preferred_amount: 10, preferred_currency: 'usd') }

      it 'still applies the discount' do
        order = order_with_amounts(50, 50)

        expect(shares(order)).to eq([BigDecimal('5'), BigDecimal('5')])
      end
    end

    context 'when the fixed amount exceeds the actionable total' do
      let(:amount) { 50 }

      it 'clamps the total discount to the line items total' do
        order = order_with_amounts(20, 10)

        expect(shares(order).sum).to eq(BigDecimal('30'))
      end

      it 'never discounts a line item by more than its own amount' do
        order = order_with_amounts(20, 10)

        expect(shares(order)).to eq([BigDecimal('20'), BigDecimal('10')])
      end
    end
  end

  describe '#compute with promotion rules excluding items' do
    let(:eligible_product) { create(:product, price: 50) }
    let(:excluded_product) { create(:product, price: 50) }

    let(:promotion) do
      promo = create(:promotion, store: store)
      # `products:` on create! fails validation on the join model because the
      # rule isn't persisted yet when Rails tries to build the through-records.
      # `product_ids_to_add=` + save is the interface the model itself uses
      # (see its `after_save :add_products` callback).
      rule = Spree::Promotion::Rules::Product.create!(promotion: promo)
      rule.product_ids_to_add = [eligible_product.id]
      rule.save!

      # `Spree::Promotion` validates_associated :rules on its own create,
      # which memoizes an empty `rules` collection on this exact `promo`
      # instance before the rule above exists. Reload so the promotion
      # object handed to the action sees the freshly created rule.
      promo.reload
    end

    let(:action) do
      Spree::Promotion::Actions::CreateItemAdjustments.create!(
        promotion: promotion,
        calculator: described_class.new(preferred_amount: 10, preferred_currency: 'USD')
      )
    end

    let(:calculator) { action.calculator }

    let(:order) do
      order = create(:order, store: store, currency: 'USD')
      create(:line_item, order: order, variant: eligible_product.master, price: 50, quantity: 1, currency: 'USD')
      create(:line_item, order: order, variant: excluded_product.master, price: 50, quantity: 1, currency: 'USD')
      order.reload
    end

    def line_item_for(product)
      order.line_items.detect { |item| item.variant_id == product.master.id }
    end

    it 'gives excluded line items no discount' do
      expect(calculator.compute(line_item_for(excluded_product))).to eq(0)
    end

    it 'does not let excluded items dilute the eligible items share' do
      # The whole 10 lands on the single eligible item, not 5 -- the excluded
      # item must be out of the denominator, not merely zeroed in the numerator.
      expect(calculator.compute(line_item_for(eligible_product))).to eq(BigDecimal('10'))
    end
  end

  describe '#compute with apply_only_on_full_priced_items' do
    subject(:calculator) do
      described_class.new(
        preferred_amount: 10,
        preferred_currency: 'USD',
        preferred_apply_only_on_full_priced_items: true
      )
    end

    let(:sale_product) { create(:product, price: 50, compare_at_price: 80) }
    let(:full_priced_product) { create(:product, price: 50) }

    let(:order) do
      order = create(:order, store: store, currency: 'USD')
      create(:line_item, order: order, variant: sale_product.master, price: 50, quantity: 1, currency: 'USD')
      create(:line_item, order: order, variant: full_priced_product.master, price: 50, quantity: 1, currency: 'USD')
      order.reload
    end

    def line_item_for(product)
      order.line_items.detect { |item| item.variant_id == product.master.id }
    end

    it 'gives sale items no discount' do
      expect(calculator.compute(line_item_for(sale_product))).to eq(0)
    end

    it 'does not let sale items dilute the full priced items share' do
      expect(calculator.compute(line_item_for(full_priced_product))).to eq(BigDecimal('10'))
    end
  end

  describe '.description' do
    it 'is translated' do
      expect(described_class.description).to eq('Fixed Amount (spread across line items)')
    end
  end
end
