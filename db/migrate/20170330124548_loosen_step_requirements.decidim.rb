# frozen_string_literal: true

# This migration comes from decidim (originally 20170116135237)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class LoosenStepRequirements < ActiveRecord::Migration[5.0]
  def change
    change_column_null(:decidim_participatory_process_steps, :short_description, true)
    change_column_null(:decidim_participatory_process_steps, :description, true)
  end
end
