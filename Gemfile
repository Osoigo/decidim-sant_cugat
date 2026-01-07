# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.2.2'

DECIDIM_VERSION = { git: "https://github.com/decidim/decidim.git", branch: "release/0.29-stable" }.freeze

gem 'dotenv-rails', '~> 2.1', '>= 2.1.1'
gem 'decidim', DECIDIM_VERSION
gem "decidim-templates", DECIDIM_VERSION

# A Decidim module to customize the localized terms in the system.
# Read more: https://github.com/mainio/decidim-module-term_customizer
# TODO: Re-enable when 0.29 compatible version is available
# gem "decidim-term_customizer", git: "https://github.com/mainio/decidim-module-term_customizer.git", branch: "main"
gem "decidim-verify_wo_registration", git: "https://github.com/CodiTramuntana/decidim-verify_wo_registration.git", branch: "master"
gem "decidim-decidim_awesome", git: "https://github.com/decidim-ice/decidim-module-decidim_awesome.git", branch: "release/0.29-stable"

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
  gem 'capistrano', '~> 3.17', require: false
  gem 'rvm1-capistrano3', require: false
  gem 'capistrano-bundler'
  gem 'capistrano-rails', require: false
  gem 'capistrano-nvm', require: false
  gem 'capistrano-passenger'

  gem 'ed25519', '>= 1.2', '< 2.0'
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0'
end

group :production, :staging do
  # # passenger 6 and later (currently 6.0.27) incompatibility with rackup 1.0.1  https://github.com/phusion/passenger/issues/2602
  # gem "passenger", "5.3.7", require: "phusion_passenger/rack_handler"
  gem "passenger", git: "https://github.com/phusion/passenger.git", branch: "stable-6.1"
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
