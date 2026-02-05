# frozen_string_literal: true

# This migration comes from decidim (originally 20170120120733)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class AddUserGroupsVerified < ActiveRecord::Migration[5.0]
  def change
    add_column :decidim_user_groups, :verified, :boolean, default: false
  end
end
