# OVH S3: Force public-read ACL for direct uploads
Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    after_create_commit :apply_public_acl_for_ovh

    private

    def apply_public_acl_for_ovh
      return unless service.is_a?(ActiveStorage::Service::S3Service)
      return unless service.public? # respeta tu config, solo si public: true
      return if uploaded_by_attacher? # variants están OK, solo direct

      begin
        service.client.put_object_acl(
          bucket: service.bucket.name,
          key: key,
          acl: "public-read"
        )
      rescue => e
        Rails.logger.error("Failed to apply public-read ACL to #{key}: #{e.message}")
      end
    end
  end
end

