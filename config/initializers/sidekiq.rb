# frozen_string_literal: true

require "sidekiq/web"

redis_database = { url: ENV.fetch("REDIS_URL") }
sidekiq_log_level = ENV.fetch("SIDEKIQ_LOG_LEVEL", ENV.fetch("RAILS_LOG_LEVEL", "info")).upcase
sidekiq_log_to_stdout = ENV["SIDEKIQ_LOG_TO_STDOUT"].present? || ENV["RAILS_LOG_TO_STDOUT"].present?

build_sidekiq_logger = lambda do
  logger = if sidekiq_log_to_stdout
    Sidekiq::Logger.new($stdout)
  else
    # Rotate daily, keep 10 days of history.
    Sidekiq::Logger.new(Rails.root.join("log", "sidekiq.log"), 10, "daily")
  end

  logger.level = Logger.const_get(sidekiq_log_level)
  logger
rescue NameError
  logger.level = Logger::INFO
  logger
end

Sidekiq.configure_server do |config|
  config.redis = redis_database
  config.logger = build_sidekiq_logger.call
end

Sidekiq.configure_client do |config|
  config.redis = redis_database
end
