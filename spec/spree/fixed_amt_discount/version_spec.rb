# frozen_string_literal: true

require "spec_helper"

RSpec.describe(Spree::FixedAmtDiscount) do
  it("exposes a version string") { expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/) }

  it("loads its engine") { expect(defined?(Spree::FixedAmtDiscount::Engine)).to eq("constant") }
end
