# frozen_string_literal: true

# Migration to create tenants table
# Each tenant represents a customer/organization with isolated data
class CreateTenants < ActiveRecord::Migration[8.0]
  def change
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :api_key_hash, null: false
      t.integer :document_quota, default: 1_000_000, null: false
      t.integer :rate_limit_per_minute, default: 1000, null: false

      t.timestamps
    end

    add_index :tenants, :subdomain, unique: true
    add_index :tenants, :api_key_hash, unique: true
  end
end
