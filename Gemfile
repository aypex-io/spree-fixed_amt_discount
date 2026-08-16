# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'pg'
gem 'propshaft'
gem 'spree_dev_tools'

# spree_dev_tools depends on this transitively (for `assigns` in controller
# specs) but never requires it, and it is a Railtie -- requiring it after boot
# is too late to hook in. List it explicitly so Bundler.require pulls it in
# before Rails.application initializes.
group :test do
  gem 'rails-controller-testing'
end

group :development, :test do
  gem 'rubocop', require: false
end
