# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.1.2'

DECIDIM_VERSION = { git: "https://github.com/decidim/decidim.git", branch: "release/0.28-stable" }.freeze

gem 'decidim', DECIDIM_VERSION
gem "decidim-templates", DECIDIM_VERSION

# A Decidim module to customize the localized terms in the system.
# Read more: https://github.com/mainio/decidim-module-term_customizer
gem "decidim-term_customizer", git: "https://github.com/mainio/decidim-module-term_customizer.git", branch: "main"
gem "decidim-verify_wo_registration", git: "https://github.com/CodiTramuntana/decidim-verify_wo_registration.git", branch: "master"
gem "decidim-decidim_awesome", git: "https://github.com/decidim-ice/decidim-module-decidim_awesome.git", branch: "release/0.28-stable" # branch: "users_autoblock"

gem 'doorkeeper', '5.7.0'

gem 'faker'
gem 'puma'
gem 'uglifier'
gem "progressbar"
gem "json", "2.9.1"

# Performance
# gem "appsignal"

group :development, :test do
  gem 'byebug', platform: :mri
  gem 'decidim-dev', DECIDIM_VERSION
end

group :development do
  gem 'listen'
  gem 'spring-commands-rspec'
end

group :production, :staging do
  gem 'dalli'
  gem 'sendgrid-ruby'
  gem 'sidekiq', '~> 6.5', '>= 6.5.7'
  gem 'fog-aws'
  gem "aws-sdk-s3", require: false
  # security fix for excon gem, which is a fog-aws dependency
  gem 'excon', '>= 0.71.0'
end

group :test do
  gem 'database_cleaner'
  gem 'rspec-rails'
end
