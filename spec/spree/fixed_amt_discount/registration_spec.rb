# frozen_string_literal: true

require 'spec_helper'

RSpec.describe('calculator registration') do
  let(:registered) do
    Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments
  end

  it('registers the calculator for per-line-item promotion adjustments') do
    expect(registered).to include(Spree::Calculator::FixedAmountOnLineItems)
  end

  it('leaves the core calculators registered') do
    expect(registered).to include(Spree::Calculator::PercentOnLineItem)
  end

  it('registers the calculator exactly once') do
    expect(registered.count(Spree::Calculator::FixedAmountOnLineItems)).to eq(1)
  end
end
