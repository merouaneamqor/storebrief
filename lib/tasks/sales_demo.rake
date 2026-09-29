# frozen_string_literal: true

namespace :sales_demo do
  desc "Seed (or refresh) the Nour Markets sales-demo tenant. Skips if already present unless FORCE_SALES_DEMO_SEED=1."
  task seed: :environment do
    if Tenant.exists?(slug: SalesDemoSeeder::SLUG) && ENV["FORCE_SALES_DEMO_SEED"] != "1"
      puts "Sales demo already present (#{SalesDemoSeeder::SLUG}) — skip. Set FORCE_SALES_DEMO_SEED=1 to refresh."
      next
    end

    tenant = SalesDemoSeeder.seed!
    puts "Sales demo ready: #{tenant.name} (#{tenant.slug})"
    puts "  Password: #{SalesDemoSeeder::PASSWORD}"
    puts "  HQ:      #{SalesDemoSeeder::HQ_EMAIL}"
    puts "  Store:   #{SalesDemoSeeder::STORE_EMAIL}"
    puts "  Admin:   #{SalesDemoSeeder::ADMIN_EMAIL} (leave brand blank at login)"
  end
end
