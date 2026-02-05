# frozen_string_literal: true

# This migration comes from decidim (originally 20180123125452)
# This file has been modified by `decidim upgrade:migrations` task on 2026-02-05 15:38:44 UTC
class AddOmnipresentBannerUrlToDecidimOrganizations < ActiveRecord::Migration[5.1]
  def change
    add_column :decidim_organizations, :omnipresent_banner_url, :string
  end
end
