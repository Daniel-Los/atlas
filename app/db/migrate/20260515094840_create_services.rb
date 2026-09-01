class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.string  :name,          null: false
      t.string  :profile,       null: false  # geocoding | routing | pois | transit | basemap
      t.boolean :enabled,       null: false, default: false
      t.integer :status,        null: false, default: 0  # enum
      t.string  :phase
      t.float   :progress
      t.text    :last_log
      t.text    :last_error
      t.bigint  :disk_bytes,    null: false, default: 0
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :services, :name, unique: true
    add_index :services, :enabled
  end
end
