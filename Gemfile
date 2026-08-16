source 'https://rubygems.org'

gemspec

gem 'pg'
gem 'propshaft'

# spree_dev_tools depends on this transitively (for `assigns` in controller
# specs) but never requires it, and it is a Railtie -- requiring it after boot
# is too late to hook in. List it explicitly so Bundler.require pulls it in
# before Rails.application initializes.
group :test do
  gem 'rails-controller-testing'
end
