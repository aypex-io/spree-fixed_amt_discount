# frozen_string_literal: true

# Bundler auto-requires a gem by its *name*, so `gem "spree-fixed_amt_discount"`
# in a host Gemfile issues `require "spree-fixed_amt_discount"`. The real entry
# point is `spree/fixed_amt_discount` (matching the Spree::FixedAmtDiscount
# namespace), so this shim keeps the default `Bundler.require` working.
require 'spree/fixed_amt_discount'
