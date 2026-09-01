class AddAutoUpdateFieldsToServices < ActiveRecord::Migration[8.0]
  def change
    change_table :services do |t|
      t.boolean  :auto_update_enabled,   default: false, null: false
      t.string   :update_schedule_cron
      t.datetime :dataset_updated_at
      t.datetime :last_update_check_at
      t.string   :last_update_status
      t.text     :last_update_error
      t.integer  :last_update_duration_s
      t.string   :pinned_image_tag
    end

    add_index :services, :auto_update_enabled
    add_index :services, :last_update_status
  end
end
