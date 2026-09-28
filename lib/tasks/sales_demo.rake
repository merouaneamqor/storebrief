# frozen_string_literal: true

namespace :sales_demo do
  desc "Seed (or refresh) the Nour Markets sales-demo tenant"
  task seed: :environment do
    tenant = SalesDemoSeeder.seed!
    puts "Sales demo ready: #{tenant.name} (#{tenant.slug})"
    puts "  Password: #{SalesDemoSeeder::PASSWORD}"
    puts "  HQ:      #{SalesDemoSeeder::HQ_EMAIL}"
    puts "  Store:   #{SalesDemoSeeder::STORE_EMAIL}"
    puts "  Admin:   #{SalesDemoSeeder::ADMIN_EMAIL} (leave brand blank at login)"
  end
end
