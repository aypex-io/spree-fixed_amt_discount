# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# CI runs a matrix of Spree versions. SPREE_VERSION pins one (e.g. "6.0.0");
# left unset, Bundler resolves the newest release the gemspec allows.
gem "spree", ENV["SPREE_VERSION"] unless ENV["SPREE_VERSION"].to_s.empty?

gem "pg"
gem "propshaft"
gem "spree_dev_tools", ">= 1.0.0.beta2"

# spree_dev_tools depends on this transitively (for `assigns` in controller
# specs) but never requires it, and it is a Railtie -- requiring it after boot
# is too late to hook in. List it explicitly so Bundler.require pulls it in
# before Rails.application initializes.
group :test do
  gem "rails-controller-testing"
end

group :development, :test do
  gem "standard", ">= 1.35.1", require: false
end
