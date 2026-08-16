# spree-fixed_amt_discount Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Spree promotion calculator that spreads one fixed discount amount pro-rata across the actionable line items, so per-item tax recalculates correctly, and publish it as `spree-fixed_amt_discount` 0.1.0.

**Architecture:** A single `Spree::Calculator` subclass registered into Spree's existing `promotion_actions_create_item_adjustments` list. It reaches the promotion via `calculable.promotion` to determine the actionable set itself, so no Spree core class is decorated or replaced. Core's `CreateItemAdjustments#compute_amount` supplies the negation and the negative-order-total guard for free.

**Tech Stack:** Ruby >= 3.3, Rails engine, Spree >= 5.6.0, RSpec via `spree_dev_tools` against a generated dummy app, PostgreSQL in CI, GitHub Actions, RubyGems Trusted Publishing (OIDC).

**Spec:** `docs/superpowers/specs/2026-08-16-spree-fixed-amt-discount-design.md`

## Global Constraints

- Spree floor is **`>= 5.6.0`**. No back-compat shims, no Appraisals matrix.
- `required_ruby_version` is **`>= 3.3`**.
- Runtime dependency is **`spree` only**. Do NOT add `spree_admin` — this gem ships no admin views.
- **No monkey-patching of Spree core.** No file may be named `*_decorator.rb`, and no core class may be reopened.
- Calculator class name is **`Spree::Calculator::FixedAmountOnLineItems`** — persisted in `spree_calculators.type`, so it is fixed from first release.
- Gem name `spree-fixed_amt_discount`; namespace `Spree::FixedAmtDiscount`; require path `spree/fixed_amt_discount`; `engine_name` `spree_fixed_amt_discount`.
- Licence MIT, author `Aypex`, email `hello@aypex.io`, `rubygems_mfa_required` = `'true'`.
- First release is **0.1.0** (not 5.x — this gem does not shadow Spree's version line).
- Repository: `aypex-io/spree-fixed_amt_discount`, public.
- `compute` returns a **non-negative** value. Core negates it.
- Commit after every task.

---

### Task 1: Scaffold the gem so an empty suite runs green

**Files:**
- Create: `spree-fixed_amt_discount.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `.rspec`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `lib/spree-fixed_amt_discount.rb`
- Create: `lib/spree/fixed_amt_discount.rb`
- Create: `lib/spree/fixed_amt_discount/version.rb`
- Create: `lib/spree/fixed_amt_discount/engine.rb`
- Create: `.github/workflows/ci.yml`
- Test: `spec/spec_helper.rb`, `spec/spree/fixed_amt_discount/version_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Spree::FixedAmtDiscount::VERSION` (String), `Spree::FixedAmtDiscount::Engine` (a `Rails::Engine`), and a bootable dummy app at `spec/dummy` that later tasks run specs against.

**Why two entry-point files:** Bundler auto-requires a gem by its *name*, so a host `gem 'spree-fixed_amt_discount'` issues `require 'spree-fixed_amt_discount'`. The real entry point is `spree/fixed_amt_discount`, matching the namespace. The hyphenated file is a one-line shim so `Bundler.require` works without consumers writing `require:` themselves.

- [ ] **Step 1: Create the gemspec**

`spree-fixed_amt_discount.gemspec`:

```ruby
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
```

- [ ] **Step 2: Create the Gemfile**

`Gemfile`:

```ruby
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
```

- [ ] **Step 3: Create the version, entry points and engine**

`lib/spree/fixed_amt_discount/version.rb`:

```ruby
module Spree
  module FixedAmtDiscount
    VERSION = '0.1.0'.freeze
  end
end
```

`lib/spree/fixed_amt_discount/engine.rb`:

```ruby
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
```

`lib/spree/fixed_amt_discount.rb`:

```ruby
# frozen_string_literal: true

require 'spree/core'
require 'spree/fixed_amt_discount/version'
require 'spree/fixed_amt_discount/engine'
```

`lib/spree-fixed_amt_discount.rb`:

```ruby
# frozen_string_literal: true

# Bundler auto-requires a gem by its *name*, so `gem "spree-fixed_amt_discount"`
# in a host Gemfile issues `require "spree-fixed_amt_discount"`. The real entry
# point is `spree/fixed_amt_discount` (matching the Spree::FixedAmtDiscount
# namespace), so this shim keeps the default `Bundler.require` working.
require 'spree/fixed_amt_discount'
```

- [ ] **Step 4: Create the Rakefile**

`Rakefile`. Note `LIB_NAME` must be the **slash** form: `common:test_app` does a literal `require ENV['LIB_NAME']`. It then tries `require "generators/#{LIB_NAME}/install/install_generator"` and rescues `LoadError` — this gem ships no generator and no migrations, so that rescue is the expected path and the "Skipping installation no generator to run..." message in the output is correct, not a failure.

```ruby
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
```

- [ ] **Step 5: Create `.rspec`, `.gitignore` and `LICENSE`**

`.rspec`:

```
--color
-r spec_helper
-f documentation
```

`.gitignore`:

```
spec/dummy/
pkg/
tmp/
log/
coverage/
.bundle/
Gemfile.lock
*.gem
```

`LICENSE`: the standard MIT licence text, `Copyright (c) 2026 Aypex`.

- [ ] **Step 6: Create the spec helper and a version spec**

`spec/spec_helper.rb`:

```ruby
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb', __FILE__)
require 'spree_dev_tools/rspec/spec_helper'

Dir[File.join(File.dirname(__FILE__), 'support/**/*.rb')].sort.each { |f| require f }
```

`spec/spree/fixed_amt_discount/version_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe Spree::FixedAmtDiscount do
  it 'exposes a version string' do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'loads its engine' do
    expect(defined?(Spree::FixedAmtDiscount::Engine)).to eq('constant')
  end
end
```

- [ ] **Step 7: Create the CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  tests:
    name: Tests
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: password
          POSTGRES_DB: spree_test
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DB: postgres
      DATABASE_URL: postgres://postgres:password@localhost:5432/spree_test
      RAILS_ENV: test
      CI: true
    steps:
      - uses: actions/checkout@v6
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
      - name: Install libvips
        run: sudo apt-get update && sudo apt-get install -y libvips
      - name: Create test app
        run: bundle exec rake test_app
      - name: Run specs
        run: bundle exec rspec --format progress
```

- [ ] **Step 8: Build the dummy app and run the suite**

Run:

```bash
bundle install
bundle exec rake test_app
bundle exec rspec
```

Expected: dummy app generates (with "Skipping installation no generator to run..." in the output), then 2 examples, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Scaffold spree-fixed_amt_discount gem and spec harness"
```

---

### Task 2: Pro-rata split with exact penny reconciliation

The core maths. No promotion filtering and no clamping yet — those are Tasks 3 and 4.

**Files:**
- Create: `app/models/spree/calculator/fixed_amount_on_line_items.rb`
- Create: `config/locales/en.yml`
- Test: `spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

**Interfaces:**
- Consumes: `Spree::FixedAmtDiscount::Engine` from Task 1 (the engine's `app/` path is what makes this model autoloadable).
- Produces: `Spree::Calculator::FixedAmountOnLineItems`, a `Spree::Calculator` subclass with preferences `amount` (decimal), `currency` (string) and `apply_only_on_full_priced_items` (boolean), and a public `compute(line_item)` returning a non-negative `BigDecimal`.

**Background for the implementer:** Spree calls `compute` once per line item. Naively rounding each item's share to 2dp loses or gains pennies, so the shares would not sum to the promised amount. The fix: every item except the last gets its rounded pro-rata share; the **last** item (deterministically, the highest `id`) gets `budget` minus the sum of all the earlier shares, absorbing the remainder.

- [ ] **Step 1: Write the failing specs**

`spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe Spree::Calculator::FixedAmountOnLineItems do
  subject(:calculator) { described_class.new(preferred_amount: amount, preferred_currency: 'USD') }

  let(:amount) { 10 }
  let(:store) { Spree::Store.default }

  # Builds a persisted order whose line items have exactly the given amounts.
  def order_with_amounts(*amounts)
    order = create(:order, store: store, currency: 'USD')
    amounts.each do |item_amount|
      create(:line_item, order: order, price: item_amount, quantity: 1, currency: 'USD')
    end
    order.reload
  end

  def shares(order)
    order.line_items.sort_by(&:id).map { |item| calculator.compute(item) }
  end

  describe '#compute' do
    it 'splits evenly across equal line items' do
      order = order_with_amounts(50, 50)

      expect(shares(order)).to eq([BigDecimal('5'), BigDecimal('5')])
    end

    it 'gives a single line item the whole amount' do
      order = order_with_amounts(50)

      expect(shares(order)).to eq([BigDecimal('10')])
    end

    it 'weights the split by line item value' do
      order = order_with_amounts(75, 25)

      expect(shares(order)).to eq([BigDecimal('7.5'), BigDecimal('2.5')])
    end

    it 'reconciles rounding pennies so the shares sum to exactly the amount' do
      order = order_with_amounts(33.33, 33.33, 33.34)

      result = shares(order)

      expect(result.sum).to eq(BigDecimal('10'))
      expect(result).to eq([BigDecimal('3.33'), BigDecimal('3.33'), BigDecimal('3.34')])
    end

    it 'returns amounts rounded to two decimal places' do
      order = order_with_amounts(10, 20, 70)

      shares(order).each do |share|
        expect(share).to eq(share.round(2))
      end
    end

    it 'returns 0 when there are no line items' do
      order = create(:order, store: store, currency: 'USD')
      line_item = build(:line_item, order: order, price: 10, quantity: 1)

      expect(calculator.compute(line_item)).to eq(0)
    end

    it 'returns 0 when given nil' do
      expect(calculator.compute(nil)).to eq(0)
    end
  end

  describe '.description' do
    it 'is translated' do
      expect(described_class.description).to eq('Fixed Amount (spread across line items)')
    end
  end
end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

Expected: FAIL — `uninitialized constant Spree::Calculator::FixedAmountOnLineItems`.

- [ ] **Step 3: Write the calculator**

`app/models/spree/calculator/fixed_amount_on_line_items.rb`:

```ruby
require_dependency 'spree/calculator'

module Spree
  # Spreads a single fixed discount amount across the actionable line items in
  # proportion to their value, so each item carries its own share and Spree
  # recalculates per-item tax against it.
  class Calculator::FixedAmountOnLineItems < Calculator
    preference :amount, :decimal, default: 0
    preference :currency, :string, default: -> { Spree::Store.default.default_currency }
    preference :apply_only_on_full_priced_items, :boolean, default: false

    def self.description
      Spree.t(:fixed_amount_on_line_items)
    end

    # Returns this line item's non-negative share of the fixed amount.
    # Spree::Promotion::Actions::CreateItemAdjustments negates the result and
    # applies its own guard against a negative order total.
    def compute(line_item = nil)
      return 0 if line_item.nil?
      return 0 unless preferred_currency.to_s.casecmp(line_item.currency.to_s).zero?

      items = actionable_line_items(line_item.order)
      return 0 unless items.include?(line_item)

      total = items.sum(&:amount)
      return 0 unless total.positive?

      budget = preferred_amount

      if line_item == items.last
        # The last item absorbs the rounding remainder so the shares sum to
        # exactly the budget rather than drifting by a penny or two.
        budget - items[0..-2].sum { |item| pro_rata(item, budget, total) }
      else
        pro_rata(line_item, budget, total)
      end
    end

    private

    def pro_rata(item, budget, total)
      (budget * item.amount / total).round(2)
    end

    def actionable_line_items(order)
      return [] if order.nil?

      # Sorted by id so "the last item" -- the one absorbing the remainder --
      # is the same on every call. Core only computes against persisted line
      # items; the to_i keeps an unsaved one from raising on comparison.
      order.line_items.to_a.sort_by { |item| item.id.to_i }
    end
  end
end
```

`config/locales/en.yml`:

```yaml
en:
  spree:
    fixed_amount_on_line_items: "Fixed Amount (spread across line items)"
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

Expected: PASS, 8 examples, 0 failures.

> If the `:line_item` factory rejects a `currency` attribute on Spree 5.6, drop
> it — the line item inherits its order's currency. Adapt the *setup* to whatever
> the factories accept; the assertions are the contract and must not change.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add FixedAmountOnLineItems calculator with pro-rata penny reconciliation"
```

---

### Task 3: Currency guard and clamping to the actionable total

**Files:**
- Modify: `app/models/spree/calculator/fixed_amount_on_line_items.rb`
- Test: `spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

**Interfaces:**
- Consumes: `Spree::Calculator::FixedAmountOnLineItems#compute(line_item)` from Task 2.
- Produces: no new public surface — same `compute(line_item)` signature, with the clamp and the per-item cap applied.

**Background:** when the fixed amount exceeds the total of the actionable items (a £50 promo on a £30 basket), the discount clamps to that total so the order lands on zero and never goes negative. This matches core's `PercentOnLineItem`. The per-item `min` guard means a contrived basket can finish up to one penny short of the budget; that is accepted, documented behaviour.

- [ ] **Step 1: Write the failing specs**

Append inside the `describe '#compute'` block of `spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`:

```ruby
    context 'when the currency does not match' do
      subject(:calculator) { described_class.new(preferred_amount: 10, preferred_currency: 'GBP') }

      it 'returns 0' do
        order = order_with_amounts(50, 50)

        expect(shares(order)).to eq([0, 0])
      end
    end

    context 'when the currency matches in a different case' do
      subject(:calculator) { described_class.new(preferred_amount: 10, preferred_currency: 'usd') }

      it 'still applies the discount' do
        order = order_with_amounts(50, 50)

        expect(shares(order)).to eq([BigDecimal('5'), BigDecimal('5')])
      end
    end

    context 'when the fixed amount exceeds the actionable total' do
      let(:amount) { 50 }

      it 'clamps the total discount to the line items total' do
        order = order_with_amounts(20, 10)

        expect(shares(order).sum).to eq(BigDecimal('30'))
      end

      it 'never discounts a line item by more than its own amount' do
        order = order_with_amounts(20, 10)

        expect(shares(order)).to eq([BigDecimal('20'), BigDecimal('10')])
      end
    end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb -e 'exceeds the actionable total'`

Expected: FAIL — the clamp is missing, so the shares sum to 50 rather than 30. (The currency examples already pass; the guard was written in Task 2. Keep them — they pin behaviour that later tasks could break.)

- [ ] **Step 3: Apply the clamp and the per-item cap**

In `compute`, replace the `budget` assignment and the branch that follows it:

```ruby
      # Clamp: a fixed amount larger than the basket discounts it to zero, never
      # below. Matches Spree::Calculator::PercentOnLineItem.
      budget = [preferred_amount, total].min

      share =
        if line_item == items.last
          # The last item absorbs the rounding remainder so the shares sum to
          # exactly the budget rather than drifting by a penny or two.
          budget - items[0..-2].sum { |item| pro_rata(item, budget, total) }
        else
          pro_rata(line_item, budget, total)
        end

      [share, line_item.amount].min
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

Expected: PASS, 12 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Clamp fixed amount to the actionable line items total"
```

---

### Task 4: Filter to actionable line items only

**Files:**
- Modify: `app/models/spree/calculator/fixed_amount_on_line_items.rb`
- Test: `spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

**Interfaces:**
- Consumes: `Spree::Calculator::FixedAmountOnLineItems#compute(line_item)` from Task 3.
- Produces: no new public surface. Adds private `#promotion` returning `Spree::Promotion` or `nil` via `calculable.try(:promotion)`.

**Background — the load-bearing detail:** items excluded by the promotion's rules must drop out of **both** the numerator and the **denominator**. If an excluded item stayed in the denominator, the remaining items would share a diluted discount and the total applied would come out under the promised amount. The spec below asserts exactly that.

The calculator reaches the promotion through associations core already provides: `calculator.calculable` is the `Spree::Promotion::Actions::CreateItemAdjustments`, which `belongs_to :promotion`. When there is no `calculable` (a bare calculator in a unit spec), every line item is treated as actionable.

`apply_only_on_full_priced_items` mirrors both sibling core calculators: items with a `compare_at_amount_in(currency)` present are on sale and are excluded, again from both numerator and denominator.

- [ ] **Step 1: Write the failing specs**

Append to `spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`, inside the top-level `describe` but after the existing `describe '#compute'` block:

```ruby
  describe '#compute with promotion rules excluding items' do
    let(:eligible_product) { create(:product, price: 50) }
    let(:excluded_product) { create(:product, price: 50) }

    let(:promotion) do
      promo = create(:promotion, store: store)
      Spree::Promotion::Rules::Product.create!(
        promotion: promo,
        products: [eligible_product]
      )
      promo
    end

    let(:action) do
      Spree::Promotion::Actions::CreateItemAdjustments.create!(
        promotion: promotion,
        calculator: described_class.new(preferred_amount: 10, preferred_currency: 'USD')
      )
    end

    let(:calculator) { action.calculator }

    let(:order) do
      order = create(:order, store: store, currency: 'USD')
      create(:line_item, order: order, variant: eligible_product.master, price: 50, quantity: 1, currency: 'USD')
      create(:line_item, order: order, variant: excluded_product.master, price: 50, quantity: 1, currency: 'USD')
      order.reload
    end

    def line_item_for(product)
      order.line_items.detect { |item| item.variant_id == product.master.id }
    end

    it 'gives excluded line items no discount' do
      expect(calculator.compute(line_item_for(excluded_product))).to eq(0)
    end

    it 'does not let excluded items dilute the eligible items share' do
      # The whole 10 lands on the single eligible item, not 5 -- the excluded
      # item must be out of the denominator, not merely zeroed in the numerator.
      expect(calculator.compute(line_item_for(eligible_product))).to eq(BigDecimal('10'))
    end
  end

  describe '#compute with apply_only_on_full_priced_items' do
    subject(:calculator) do
      described_class.new(
        preferred_amount: 10,
        preferred_currency: 'USD',
        preferred_apply_only_on_full_priced_items: true
      )
    end

    let(:sale_product) { create(:product, price: 50, compare_at_price: 80) }
    let(:full_priced_product) { create(:product, price: 50) }

    let(:order) do
      order = create(:order, store: store, currency: 'USD')
      create(:line_item, order: order, variant: sale_product.master, price: 50, quantity: 1, currency: 'USD')
      create(:line_item, order: order, variant: full_priced_product.master, price: 50, quantity: 1, currency: 'USD')
      order.reload
    end

    def line_item_for(product)
      order.line_items.detect { |item| item.variant_id == product.master.id }
    end

    it 'gives sale items no discount' do
      expect(calculator.compute(line_item_for(sale_product))).to eq(0)
    end

    it 'does not let sale items dilute the full priced items share' do
      expect(calculator.compute(line_item_for(full_priced_product))).to eq(BigDecimal('10'))
    end
  end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb -e 'excluding items' -e 'apply_only_on_full_priced_items'`

Expected: FAIL — every line item is currently actionable, so both excluded items receive 5 and both eligible items receive 5 instead of 10.

- [ ] **Step 3: Filter the actionable set**

Replace the private section of `app/models/spree/calculator/fixed_amount_on_line_items.rb`:

```ruby
    private

    def pro_rata(item, budget, total)
      (budget * item.amount / total).round(2)
    end

    def actionable_line_items(order)
      return [] if order.nil?

      # Sorted by id so "the last item" -- the one absorbing the remainder --
      # is the same on every call. Core only computes against persisted line
      # items; the to_i keeps an unsaved one from raising on comparison.
      order.line_items.to_a.
        select { |item| actionable?(order, item) }.
        sort_by { |item| item.id.to_i }
    end

    # Excluded items must leave the actionable set entirely -- dropping them
    # from the numerator alone would dilute the remaining items' shares and
    # apply less than the promised amount.
    def actionable?(order, item)
      return false if preferred_apply_only_on_full_priced_items && on_sale?(item)
      return true if promotion.nil?

      promotion.line_item_actionable?(order, item)
    end

    def on_sale?(item)
      item.variant&.compare_at_amount_in(item.currency).present?
    end

    # `calculable` is the Spree::Promotion::Actions::CreateItemAdjustments this
    # calculator belongs to. A bare calculator (no action) has none.
    def promotion
      calculable.try(:promotion)
    end
```

- [ ] **Step 4: Run the full spec file to verify everything passes**

Run: `bundle exec rspec spec/models/spree/calculator/fixed_amount_on_line_items_spec.rb`

Expected: PASS, 16 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Restrict the pro-rata split to actionable line items"
```

---

### Task 5: Register the calculator with Spree

**Files:**
- Modify: `lib/spree/fixed_amt_discount/engine.rb`
- Test: `spec/spree/fixed_amt_discount/registration_spec.rb`

**Interfaces:**
- Consumes: `Spree::Calculator::FixedAmountOnLineItems` from Task 4; `Spree::FixedAmtDiscount::Engine` from Task 1.
- Produces: `Spree::Calculator::FixedAmountOnLineItems` present in `Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments` after boot.

**Background — do not skip this:** `spree_core`'s engine **assigns** that array with `=` inside its own `config.after_initialize`. A `config/initializers/*.rb` file in this gem — which is what the predecessor gem used — runs during engine initialization, i.e. *before* `after_initialize`, and is therefore silently clobbered. Registering from this engine's own `after_initialize` works because this engine is initialized after `spree_core` (it depends on it), so its block is registered later and runs later. The spec exists so this cannot regress unnoticed.

- [ ] **Step 1: Write the failing spec**

`spec/spree/fixed_amt_discount/registration_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe 'calculator registration' do
  let(:registered) do
    Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments
  end

  it 'registers the calculator for per-line-item promotion adjustments' do
    expect(registered).to include(Spree::Calculator::FixedAmountOnLineItems)
  end

  it 'leaves the core calculators registered' do
    expect(registered).to include(Spree::Calculator::PercentOnLineItem)
  end

  it 'registers the calculator exactly once' do
    expect(registered.count(Spree::Calculator::FixedAmountOnLineItems)).to eq(1)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/spree/fixed_amt_discount/registration_spec.rb`

Expected: FAIL — the array contains only core's `PercentOnLineItem`, `FlatRate` and `FlexiRate`.

- [ ] **Step 3: Register from the engine's after_initialize**

Add to `lib/spree/fixed_amt_discount/engine.rb`, inside the `Engine` class body:

```ruby
      # Must be after_initialize, not a config/initializers file: spree_core
      # ASSIGNS this array with `=` in its own after_initialize, which runs
      # after engine initializers and would clobber an earlier registration.
      # This engine is initialized after spree_core, so this block runs after
      # core's. spec/spree/fixed_amt_discount/registration_spec.rb pins it.
      config.after_initialize do
        Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments <<
          Spree::Calculator::FixedAmountOnLineItems
      end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/spree/fixed_amt_discount/registration_spec.rb`

Expected: PASS, 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Register the calculator for per-line-item promotion adjustments"
```

---

### Task 6: End-to-end promotion adjustment spec

Proves the calculator works through the real Spree promotion machinery, not just when called directly.

**Files:**
- Test: `spec/integration/fixed_amount_promotion_spec.rb`

**Interfaces:**
- Consumes: everything from Tasks 2–5.
- Produces: no production code — this task is a test-only deliverable.

**Background:** `Spree::Promotion::Actions::CreateItemAdjustments#perform` creates one adjustment per actionable line item, each calling back into `compute_amount`, which negates our `compute` and applies core's own guards. The assertion that matters is that the adjustments sum to exactly minus the fixed amount — no penny drift once the values have gone through the database as decimals.

- [ ] **Step 1: Write the failing spec**

`spec/integration/fixed_amount_promotion_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe 'fixed amount promotion applied across line items' do
  let(:store) { Spree::Store.default }

  let(:promotion) do
    promo = create(:promotion, store: store, name: 'Tenner off')
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 10,
        preferred_currency: 'USD'
      )
    )
    promo
  end

  def order_with_amounts(*amounts)
    order = create(:order, store: store, currency: 'USD')
    amounts.each do |item_amount|
      create(:line_item, order: order, price: item_amount, quantity: 1, currency: 'USD')
    end
    order.reload
  end

  def apply(order)
    promotion.actions.each { |action| action.perform(order: order, promotion: promotion) }
    order.reload
    order.update_with_updater!
    order.reload
  end

  it 'creates one adjustment per line item' do
    order = order_with_amounts(33.33, 33.33, 33.34)

    apply(order)

    expect(order.line_items.map { |item| item.adjustments.count }).to eq([1, 1, 1])
  end

  it 'discounts the order by exactly the fixed amount' do
    order = order_with_amounts(33.33, 33.33, 33.34)

    apply(order)

    expect(order.line_items.flat_map(&:adjustments).sum(&:amount)).to eq(BigDecimal('-10'))
  end

  it 'reduces the order item total by exactly the fixed amount' do
    order = order_with_amounts(50, 50)

    apply(order)

    expect(order.item_total + order.line_items.flat_map(&:adjustments).sum(&:amount)).
      to eq(BigDecimal('90'))
  end

  it 'does not drive the order total negative when the amount exceeds the basket' do
    promotion.actions.first.calculator.update!(preferred_amount: 500)
    order = order_with_amounts(20, 10)

    apply(order)

    expect(order.total).to be >= 0
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/integration/fixed_amount_promotion_spec.rb`

Expected: PASS, 4 examples, 0 failures. If any example fails, the calculator is wrong — fix the calculator, not the spec.

> If `order.update_with_updater!` is not available on Spree 5.6, use `Spree::OrderUpdater.new(order).update` instead and keep the assertions identical. Confirm which exists with:
> `bundle exec rails runner -e test 'puts Spree::Order.instance_methods.grep(/updater/).inspect'` from `spec/dummy`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Add end-to-end promotion adjustment specs"
```

---

### Task 7: Tax correctness spec

The reason this gem exists. This is the case core's `FlatRate` on a whole-order adjustment gets wrong.

**Files:**
- Test: `spec/integration/fixed_amount_promotion_tax_spec.rb`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces: no production code — test-only deliverable.

**Background:** with a VAT-inclusive rate, each line item's included tax is derived from its own discounted amount. Because this gem attaches the discount to the line items, Spree's tax adjuster recalculates each item's tax against the reduced amount. Two items on **different tax categories at different rates** is the discriminating case: an order-level adjustment cannot apportion between them, so the tax total comes out wrong; a per-item split gets it right.

Expected arithmetic for the main example — two £60 items, one at 20% VAT-inclusive and one at 5% VAT-inclusive, £12 promo split £6/£6:

- Item A: 54.00 net of discount, included tax = 54.00 × 20 / 120 = **9.00**
- Item B: 54.00 net of discount, included tax = 54.00 × 5 / 105 = **2.57** (2.5714… rounded)
- Total included tax = **11.57**

- [ ] **Step 1: Write the failing spec**

`spec/integration/fixed_amount_promotion_tax_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe 'fixed amount promotion and VAT inclusive tax' do
  let(:store) { Spree::Store.default }
  let(:zone) { create(:global_zone) }

  let(:standard_category) { create(:tax_category, name: 'Standard') }
  let(:reduced_category)  { create(:tax_category, name: 'Reduced') }

  let!(:standard_rate) do
    create(:tax_rate,
           zone: zone,
           tax_category: standard_category,
           amount: 0.20,
           included_in_price: true)
  end

  let!(:reduced_rate) do
    create(:tax_rate,
           zone: zone,
           tax_category: reduced_category,
           amount: 0.05,
           included_in_price: true)
  end

  let(:standard_product) { create(:product, price: 60, tax_category: standard_category) }
  let(:reduced_product)  { create(:product, price: 60, tax_category: reduced_category) }

  let(:promotion) do
    promo = create(:promotion, store: store, name: 'Twelve off')
    Spree::Promotion::Actions::CreateItemAdjustments.create!(
      promotion: promo,
      calculator: Spree::Calculator::FixedAmountOnLineItems.new(
        preferred_amount: 12,
        preferred_currency: 'USD'
      )
    )
    promo
  end

  let(:order) do
    order = create(:order_with_line_items,
                   store: store,
                   currency: 'USD',
                   line_items_count: 0,
                   ship_address: create(:address))
    create(:line_item, order: order, variant: standard_product.master, price: 60, quantity: 1, currency: 'USD')
    create(:line_item, order: order, variant: reduced_product.master, price: 60, quantity: 1, currency: 'USD')
    order.reload
  end

  before do
    promotion.actions.each { |action| action.perform(order: order, promotion: promotion) }
    order.reload
    order.update_with_updater!
    order.reload
  end

  def line_item_for(product)
    order.line_items.detect { |item| item.variant_id == product.master.id }
  end

  it 'splits the discount evenly across the two items' do
    expect(order.line_items.flat_map(&:adjustments).select(&:promotion?).sum(&:amount)).
      to eq(BigDecimal('-12'))
  end

  it 'recalculates the standard rated item tax against its discounted amount' do
    # 54.00 * 20 / 120
    expect(line_item_for(standard_product).included_tax_total).to eq(BigDecimal('9.00'))
  end

  it 'recalculates the reduced rated item tax against its discounted amount' do
    # 54.00 * 5 / 105, rounded
    expect(line_item_for(reduced_product).included_tax_total).to eq(BigDecimal('2.57'))
  end

  it 'produces a per-category tax total an order level adjustment could not' do
    expect(order.included_tax_total).to eq(BigDecimal('11.57'))
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/integration/fixed_amount_promotion_tax_spec.rb`

Expected: PASS, 4 examples, 0 failures.

> **If the tax totals come out as zero,** the order has no tax zone match — check that `create(:global_zone)` covers the order's ship address, and that the order has been through `update_with_updater!` after the adjustments were created. Adjust the *setup* to make tax apply; do not weaken the assertions. If Spree 5.6 rounds the reduced-rate item to `2.57` differently than expected, correct the expected value to what Spree actually computes **and update the arithmetic comment to match** — the point of the spec is that tax is computed per item against the discounted amount, not the specific rounding.

- [ ] **Step 3: Run the whole suite**

Run: `bundle exec rspec`

Expected: PASS, 29 examples, 0 failures (2 version + 16 calculator + 3 registration + 4 integration + 4 tax).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add VAT inclusive per-category tax specs"
```

---

### Task 8: README, CHANGELOG and release workflow

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `Spree::FixedAmtDiscount::VERSION` from Task 1.
- Produces: the documentation and the tag-triggered publish workflow that Task 9 relies on.

- [ ] **Step 1: Write the README**

`README.md` must cover, in this order:

1. One-paragraph statement of the problem: core's `FlatRate` on a per-line-item adjustment applies the full amount to *every* line item, and on a whole-order adjustment it lands as a single untaxed adjustment that cannot apportion tax between categories.
2. Installation: `bundle add spree-fixed_amt_discount`, requires Spree >= 5.6.
3. Usage: in the admin, Promotion → Actions → **Create per-line-item adjustment** → calculator **Fixed Amount (spread across line items)** → set amount and currency.
4. Behaviour section documenting, as prose: the pro-rata weighting by `price × quantity` before discounts; the last item (by `id`) absorbing the rounding remainder so shares sum exactly; the clamp to the actionable total when the amount exceeds the basket; and that items excluded by promotion rules leave the split entirely rather than diluting it.
5. A worked example: £10 across £33.33 / £33.33 / £33.34 → £3.33 / £3.33 / £3.34.
6. Development: `bundle install`, `bundle exec rake test_app`, `bundle exec rspec`.
7. Licence: MIT.

- [ ] **Step 2: Write the CHANGELOG**

`CHANGELOG.md`:

```markdown
# Changelog

## 0.1.0

- Initial release.
- Adds `Spree::Calculator::FixedAmountOnLineItems`, a promotion calculator that
  spreads a single fixed discount amount across the actionable line items in
  proportion to their value, so per-item tax is recalculated correctly.
- Registered automatically for per-line-item promotion adjustments.
- Requires Spree >= 5.6.
```

- [ ] **Step 3: Add the release workflow**

`.github/workflows/release.yml`:

```yaml
---
# Publishes to RubyGems.org via Trusted Publishing (OIDC) when a v* tag is
# pushed. There is no API token or secret involved: GitHub mints a short-lived
# identity token and RubyGems.org exchanges it for a push-scoped credential.
#
# Requires a trusted publisher registered on RubyGems.org for this gem with:
#   owner       aypex-io
#   repository  spree-fixed_amt_discount
#   workflow    release.yml
#   environment release
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  push:
    name: Push gem to RubyGems.org
    runs-on: ubuntu-latest

    permissions:
      contents: write
      id-token: write

    # Must match the environment registered on the RubyGems trusted publisher.
    environment: release

    steps:
      - uses: actions/checkout@v6
        with:
          # release-gem installs its own git credentials for the release task.
          persist-credentials: false

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ruby
          bundler-cache: true

      - uses: rubygems/release-gem@v1
```

- [ ] **Step 4: Verify the gem builds**

Run: `gem build spree-fixed_amt_discount.gemspec`

Expected: `Successfully built RubyGem  Name: spree-fixed_amt_discount  Version: 0.1.0`. Then `rm -f spree-fixed_amt_discount-0.1.0.gem`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add README, CHANGELOG and release workflow"
```

---

### Task 9: Publish

**Files:** none — this task is repository and registry operations.

**Interfaces:**
- Consumes: a green suite and a buildable gem from Tasks 1–8.
- Produces: `spree-fixed_amt_discount` 0.1.0 on RubyGems.org.

**This task needs the user.** Creating a public repository under `aypex-io`, registering a trusted publisher, and pushing a release tag are outward-facing and not reversible in the way a commit is. Stop and confirm with the user before each of Steps 1, 4 and 5.

- [ ] **Step 1: Create the GitHub repository (confirm with the user first)**

```bash
gh repo create aypex-io/spree-fixed_amt_discount \
  --public \
  --description "Fixed amount Spree promotion spread pro-rata across line items, so per-item tax is correct" \
  --source . --remote origin --push
```

- [ ] **Step 2: Confirm CI is green on main**

Run: `gh run watch`

Expected: the `CI / Tests` job passes. Do not proceed until it does.

- [ ] **Step 3: Create the `release` GitHub environment**

Run: `gh api -X PUT repos/aypex-io/spree-fixed_amt_discount/environments/release`

Expected: HTTP 200 with the environment JSON. The name must match `environment: release` in `release.yml`.

- [ ] **Step 4: Register the trusted publisher on RubyGems.org (user action)**

The user does this in a browser at <https://rubygems.org/profile/oidc/pending_trusted_publishers/new>, since the gem does not exist on RubyGems yet:

| Field | Value |
|---|---|
| Gem name | `spree-fixed_amt_discount` |
| Owner | `aypex-io` |
| Repository | `spree-fixed_amt_discount` |
| Workflow filename | `release.yml` |
| Environment | `release` |

Ask the user to confirm this is done before Step 5. Without it the release job fails at the OIDC exchange.

- [ ] **Step 5: Tag and push the release (confirm with the user first)**

```bash
git tag v0.1.0
git push origin v0.1.0
gh run watch
```

Expected: the `Release` workflow publishes the gem.

- [ ] **Step 6: Verify publication**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://rubygems.org/api/v1/gems/spree-fixed_amt_discount.json
```

Expected: `200`.

- [ ] **Step 7: Report to the user**

Confirm the published version, the RubyGems URL, and the repository URL.
