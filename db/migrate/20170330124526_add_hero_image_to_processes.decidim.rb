# frozen_string_literal: true

# This migration comes from decidim (originally 20161011125616)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class AddHeroImageToProcesses < ActiveRecord::Migration[5.0]
  def change
    add_column :decidim_participatory_processes, :hero_image, :string
  end
end
