# Confidential commercial pricing (Super Admin only). Seeds the initial proposed
# defaults; later changes go through the admin UI and are versioned + audited.
class CreatePricing < ActiveRecord::Migration[8.1]
  # Initial proposed defaults, MAD per store per month. nil = custom quotation.
  INITIAL_PLANS = [
    { key: "starter",    position: 1, unit_price: 199 },
    { key: "business",   position: 2, unit_price: 349 },
    { key: "enterprise", position: 3, unit_price: 499 },
    { key: "grand_compte", position: 4, unit_price: nil }
  ].freeze

  def up
    create_table :pricing_plans do |t|
      t.string :key, null: false
      t.integer :position, null: false, default: 0
      t.decimal :unit_price, precision: 10, scale: 2
      t.string :currency, null: false, default: "MAD"
      t.boolean :active_for_sales, null: false, default: true
      t.integer :max_stores
      t.decimal :max_discount_percent, precision: 5, scale: 2, null: false, default: 0
      t.jsonb :volume_tiers, null: false, default: []
      t.jsonb :limits, null: false, default: {}
      t.timestamps
      t.index :key, unique: true
    end

    create_table :pricing_plan_versions do |t|
      t.references :pricing_plan, null: false, foreign_key: true
      t.decimal :unit_price, precision: 10, scale: 2
      t.string :currency, null: false
      t.boolean :active_for_sales, null: false
      t.references :changed_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end

    create_table :quotations do |t|
      t.string :reference, null: false
      t.references :pricing_plan, null: false, foreign_key: true
      t.string :customer_name, null: false
      t.string :customer_email
      t.integer :store_count, null: false
      t.decimal :unit_price, precision: 10, scale: 2, null: false
      t.decimal :discount_percent, precision: 5, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "MAD"
      t.text :terms
      t.date :valid_until
      t.string :status, null: false, default: "draft"
      t.datetime :issued_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index :reference, unique: true
      t.index :status
    end

    create_table :pricing_audit_logs do |t|
      t.references :user, foreign_key: true
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.jsonb :changes_made, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[subject_type subject_id]
    end

    add_column :demo_requests, :country, :string
    add_column :demo_requests, :requested_plan, :string
    add_column :demo_requests, :requirements, :text

    seed_initial_plans
  end

  def down
    remove_column :demo_requests, :requirements
    remove_column :demo_requests, :requested_plan
    remove_column :demo_requests, :country
    drop_table :pricing_audit_logs
    drop_table :quotations
    drop_table :pricing_plan_versions
    drop_table :pricing_plans
  end

  private

  def seed_initial_plans
    now = Time.current
    INITIAL_PLANS.each do |plan|
      id = select_value(<<~SQL.squish)
        INSERT INTO pricing_plans (key, position, unit_price, currency, active_for_sales, created_at, updated_at)
        VALUES (#{quote(plan[:key])}, #{plan[:position]}, #{plan[:unit_price] || 'NULL'}, 'MAD', TRUE, #{quote(now)}, #{quote(now)})
        RETURNING id
      SQL
      execute(<<~SQL.squish)
        INSERT INTO pricing_plan_versions (pricing_plan_id, unit_price, currency, active_for_sales, created_at)
        VALUES (#{id}, #{plan[:unit_price] || 'NULL'}, 'MAD', TRUE, #{quote(now)})
      SQL
    end
  end
end
