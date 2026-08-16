require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
require 'spree/testing_support/extension_rake'

RSpec::Core::RakeTask.new

task :default do
  if Dir['spec/dummy'].empty?
    Rake::Task[:test_app].invoke
    Dir.chdir('../../')
  end
  Rake::Task[:spec].invoke
end

desc 'Generates a dummy app for testing'
task :test_app do
  # Must be the require path, not the gem name -- common:test_app does a literal
  # `require ENV['LIB_NAME']` and templates the same string into the dummy app.
  ENV['LIB_NAME'] = 'spree/fixed_amt_discount'
  ENV['DB'] ||= 'postgres'
  # This gem ships no admin or storefront views, so the dummy app needs neither.
  # Leaving both off also skips the Tailwind install and assets:precompile.
  Rake::Task['extension:test_app'].execute
end
