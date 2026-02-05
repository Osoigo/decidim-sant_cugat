# frozen_string_literal: true

# This migration comes from decidim (originally 20200320105923)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class IndexForeignKeysInDecidimNotifications < ActiveRecord::Migration[5.2]
  def change
    add_index :decidim_notifications, :decidim_resource_id
  end
end
