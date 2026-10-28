# frozen_string_literal: true

module Spree
  module FixedAmtDiscount
    ##
    # Rails engine that registers the fixed-amount calculator with Spree.
    #
    # Registration happens in +after_initialize+ because +spree_core+ assigns
    # +config.spree.calculators.promotion_actions_create_item_adjustments+ with
    # ++=+ in its own +after_initialize+. An engine initializer would run first
    # and be overwritten.
    #
    class Engine < ::Rails::Engine
      require "spree/core"
      isolate_namespace Spree
      engine_name "spree_fixed_amt_discount"

      config.generators do |g|
        g.test_framework :rspec
      end

      # Must be after_initialize, not a config/initializers file: spree_core
      # ASSIGNS this array with `=` in its own after_initialize, which runs
      # after engine initializers and would clobber an earlier registration.
      # This engine is initialized after spree_core, so this block runs after
      # core's. spec/spree/fixed_amt_discount/registration_spec.rb pins it.
      config.after_initialize do
        Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments <<
          Spree::Calculator::FixedAmountOnLineItems
      end
    end
  end
end
