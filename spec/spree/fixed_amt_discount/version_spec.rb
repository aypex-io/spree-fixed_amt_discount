require 'spec_helper'

RSpec.describe Spree::FixedAmtDiscount do
  it 'exposes a version string' do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'loads its engine' do
    expect(defined?(Spree::FixedAmtDiscount::Engine)).to eq('constant')
  end
end
