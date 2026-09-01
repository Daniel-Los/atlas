class CreateRegionSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :region_selections do |t|
      t.string  :region_name, null: false
      t.boolean :active,      null: false, default: true
      t.integer :position,    null: false, default: 0
      t.boolean :orphaned,    null: false, default: false
      t.timestamps
    end

    add_index :region_selections, :region_name, unique: true
  end
end
