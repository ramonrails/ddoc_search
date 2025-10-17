# frozen_string_literal: true

# Migration to create documents table
# Stores document metadata in PostgreSQL while full content is indexed in Elasticsearch
class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.string :title, null: false, limit: 500
      t.text :content, null: false
      t.string :content_hash, limit: 64
      t.bigint :file_size
      # Use json for SQLite compatibility, jsonb for PostgreSQL
      if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
        t.jsonb :metadata, default: {}
      else
        t.json :metadata
      end
      t.datetime :indexed_at

      t.timestamps
    end

    add_index :documents, [ :tenant_id, :created_at ]
    add_index :documents, :content_hash
    add_index :documents, :indexed_at
  end
end
