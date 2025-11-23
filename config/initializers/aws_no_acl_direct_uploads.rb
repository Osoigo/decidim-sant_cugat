Rails.application.config.to_prepare do
  require "active_storage/service/s3_service"

  # Remove the acl options from PUT requests for Direct Uploads
  ActiveStorage::Service::S3Service.class_eval do
    def upload_options
      (@upload_options || {}).except(:acl)
    end
  end
end
