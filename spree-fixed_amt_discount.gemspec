lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'spree/fixed_amt_discount/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree-fixed_amt_discount'
  s.version     = Spree::FixedAmtDiscount::VERSION
  s.summary     = 'Fixed amount Spree promotion spread pro-rata across line items'
  s.description = 'Adds a promotion calculator that spreads a single fixed discount amount ' \
                  'across the actionable line items in proportion to their value, so each ' \
                  "item's tax is recalculated correctly instead of the discount landing as " \
                  'one untaxed order-level adjustment.'
  s.required_ruby_version = '>= 3.3'

  s.author   = 'Aypex'
  s.email    = 'hello@aypex.io'
  s.homepage = 'https://github.com/aypex-io/spree-fixed_amt_discount'
  s.license  = 'MIT'

  s.metadata = {
    'source_code_uri' => s.homepage,
    'bug_tracker_uri' => "#{s.homepage}/issues",
    'changelog_uri' => "#{s.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  s.files = Dir['{app,config,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md', 'CHANGELOG.md']
  s.require_path = 'lib'

  s.add_dependency 'spree', '>= 5.6.0'

  s.add_development_dependency 'spree_dev_tools'
end
