class RegionSelection < ApplicationRecord
  validates :region_name, presence: true, uniqueness: true

  scope :active_names, -> { where(active: true).order(:position).pluck(:region_name) }

  def orphaned?
    !!orphaned
  end
end
