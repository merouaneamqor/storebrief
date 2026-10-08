# frozen_string_literal: true

puts "Seeding sales demo tenant (Nour Markets)..."
tenant = SalesDemoSeeder.seed!
puts "  #{tenant.name} / #{tenant.slug}"
puts "  Password: #{SalesDemoSeeder::PASSWORD}"
puts "  HQ: #{SalesDemoSeeder::HQ_EMAIL}"
puts "  Store: #{SalesDemoSeeder::STORE_EMAIL}"
