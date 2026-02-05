# frozen_string_literal: true

# This migration comes from decidim (originally 20160920141151)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class UserHasRoles < ActiveRecord::Migration[5.0]
  def change
    add_column :decidim_users, :roles, :string, array: true, default: []
  end
end
