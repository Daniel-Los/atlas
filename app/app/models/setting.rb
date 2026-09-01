class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default = nil)
    where(key: key.to_s).pick(:value) || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key.to_s)
    record.value = value
    record.save!
    record
  end

  def self.unset(key)
    where(key: key.to_s).destroy_all
  end
end
