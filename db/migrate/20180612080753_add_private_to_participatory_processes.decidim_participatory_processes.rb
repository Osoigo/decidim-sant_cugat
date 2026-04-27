# frozen_string_literal: true

# This migration comes from decidim_participatory_processes (originally 20180122110007)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class AddPrivateToParticipatoryProcesses < ActiveRecord::Migration[5.1]
  def change
    add_column :decidim_participatory_processes, :private_space, :boolean, default: false
  end
end
