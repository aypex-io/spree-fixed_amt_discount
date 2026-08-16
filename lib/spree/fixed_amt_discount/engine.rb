module Spree
  module FixedAmtDiscount
    class Engine < ::Rails::Engine
      require 'spree/core'
      isolate_namespace Spree
      engine_name 'spree_fixed_amt_discount'

      config.generators do |g|
        g.test_framework :rspec
      end
    end
  end
end
