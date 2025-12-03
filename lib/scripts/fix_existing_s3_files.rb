# frozen_string_literal: true

# Script to fix Content-Disposition headers for all existing S3 objects
# Run with: RAILS_ENV=staging S3_BUCKET=bucket-name bin/rails runner lib/scripts/fix_existing_s3_files.rb
# Required: 
#   RAILS_ENV=environment     Rails environment (REQUIRED)
#   S3_BUCKET=bucket-name     S3 bucket name (REQUIRED)
# Options: 
#   DRY_RUN=true              for dry-run mode
#   AWS_ACCESS_KEY_ID=...     AWS credentials (optional, can use Rails secrets)
#   AWS_SECRET_ACCESS_KEY=... AWS credentials (optional, can use Rails secrets)
#   AWS_DEFAULT_REGION=...    AWS region (optional, can use Rails secrets)
#
# Examples:
#   DRY_RUN=true RAILS_ENV=staging S3_BUCKET=santcugat-preproduction bin/rails runner lib/scripts/fix_existing_s3_files.rb
#   RAILS_ENV=production S3_BUCKET=santcugat-production bin/rails runner lib/scripts/fix_existing_s3_files.rb

require 'aws-sdk-s3'

class FixExistingS3Files
  def self.run
    dry_run = ENV['DRY_RUN'] == 'true'
    bucket = ENV['S3_BUCKET']
    
    # Validate required arguments
    if bucket.blank?
      puts "❌ Error: Missing required arguments"
      puts "Usage: RAILS_ENV=environment S3_BUCKET=bucket-name bin/rails runner lib/scripts/fix_existing_s3_files.rb"
      puts ""
      puts "Required environment variables:"
      puts "  RAILS_ENV=environment     Rails environment (e.g., staging, production)"
      puts "  S3_BUCKET=bucket-name     S3 bucket name"
      puts ""
      puts "Optional environment variables:"
      puts "  DRY_RUN=true              Show what would be done without making changes"
      puts "  AWS_ACCESS_KEY_ID=...     AWS credentials (or use Rails secrets)"
      puts "  AWS_SECRET_ACCESS_KEY=... AWS credentials (or use Rails secrets)"
      puts "  AWS_DEFAULT_REGION=...    AWS region (or use Rails secrets)"
      puts ""
      puts "Examples:"
      puts "  DRY_RUN=true RAILS_ENV=staging S3_BUCKET=santcugat-preproduction bin/rails runner lib/scripts/fix_existing_s3_files.rb"
      puts "  RAILS_ENV=production S3_BUCKET=santcugat-production bin/rails runner lib/scripts/fix_existing_s3_files.rb"
      exit 1
    end
    
    # Set up logging
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    log_file = "/tmp/s3_metadata_fix_#{timestamp}.log"
    
    # Create logger
    require 'logger'
    logger = Logger.new(log_file)
    logger.level = Logger::INFO
    
    # Helper method to log to both console and file
    def log_message(logger, message)
      puts message
      logger.info(message)
    end
    
    if dry_run
      puts "🔍 DRY RUN MODE - No changes will be made"
      puts "📝 Processing only 5 files as sample"
    else
      puts "🚀 LIVE MODE - Changes will be applied to ALL files"
    end
    
    puts "Starting S3 file metadata fix..."
    
    # Get S3 configuration from environment variables and Rails secrets
    # bucket is already validated above
    
    # AWS credentials priority: ENV vars > Rails secrets
    region = ENV['AWS_DEFAULT_REGION'] || Rails.application.secrets.dig(:storage, :s3, :region)
    access_key_id = ENV['AWS_ACCESS_KEY_ID'] || Rails.application.secrets.dig(:storage, :s3, :access_key_id)
    secret_access_key = ENV['AWS_SECRET_ACCESS_KEY'] || Rails.application.secrets.dig(:storage, :s3, :secret_access_key)
    
    # Validate credentials
    if access_key_id.blank? || secret_access_key.blank?
      puts "❌ Error: AWS credentials are required"
      puts "Please set AWS credentials using one of these methods:"
      puts "1. Environment variables: AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... bin/rails runner ..."
      puts "2. Configure Rails secrets in secrets.yml"
      puts "3. AWS CLI profile: aws configure"
      exit 1
    end
    
    puts "Bucket: #{bucket}"
    puts "Region: #{region}"
    puts "Rails Environment: #{Rails.env}"
    puts "AWS Access Key: #{access_key_id[0..7]}..."
    puts "Log file: #{log_file}"
    puts "=" * 50
    
    # Initial log entries
    log_message(logger, "S3 metadata fix started at #{Time.now}")
    log_message(logger, "Mode: #{dry_run ? 'DRY RUN' : 'LIVE'}")
    log_message(logger, "Bucket: #{bucket}")
    log_message(logger, "Rails Environment: #{Rails.env}")
    log_message(logger, "=" * 50)
    
    s3_client = Aws::S3::Client.new(
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    )
    
    total_count = 0
    success_count = 0
    error_count = 0
    start_time = Time.now
    
    # Get total count for progress tracking
    unless dry_run
      total_files = ActiveStorage::Blob.count
      puts "Total files in database: #{total_files.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      log_message(logger, "Total files in database: #{total_files}")
    end
    
    # Process Active Storage blobs with optimized batch size
    batch_size = dry_run ? 5 : 1000
    blobs_query = dry_run ? ActiveStorage::Blob.limit(5) : ActiveStorage::Blob
    
    blobs_query.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |blob|
        total_count += 1
        filename = blob.filename.sanitized
        content_type = blob.content_type
        
        # Determine disposition based on content type
        disposition = if content_type&.start_with?('image/')
          "inline; filename=\"#{filename}\""
        else
          "attachment; filename=\"#{filename}\""
        end
        
        # Show progress every 100 files for dry run, every 1000 for live
        progress_interval = dry_run ? 1 : 1000
        if (total_count % progress_interval == 0) || total_count == 1
          progress_percent = dry_run ? (total_count * 100.0 / 5).round(1) : 
                           (total_files ? (total_count * 100.0 / total_files).round(1) : 0)
          puts "Processing: #{filename} (#{total_count}#{total_files ? "/#{total_files}" : ''} - #{progress_percent}%)"
          
          if dry_run || (total_count % progress_interval == 0)
            puts "  Content-Type: #{content_type}"
            puts "  Disposition: #{disposition}"
          end
        end
        
        log_message(logger, "Processing file #{total_count} - #{filename} (key: #{blob.key})")
      log_message(logger, "  Content-Type: #{content_type}, Disposition: #{disposition}")
      
      begin
        if dry_run
          # Dry run - just show what would be done
          puts "  🔍 Would update with:"
          puts "    Content-Type: #{content_type}"
          puts "    Content-Disposition: #{disposition}"
          log_message(logger, "  DRY RUN - Would set metadata")
          success_count += 1
        else
          # Copy object to itself with proper metadata
          s3_client.copy_object(
            bucket: bucket,
            copy_source: "#{bucket}/#{blob.key}",
            key: blob.key,
            content_type: content_type,
            content_disposition: disposition,
            metadata_directive: 'REPLACE'
          )
          
          success_count += 1
          puts "  ✅ Success!"
          log_message(logger, "  SUCCESS - Updated metadata")
        end
        
      rescue Aws::S3::Errors::NotFound
        error_count += 1
        puts "  ❌ Error: File not found in S3"
        log_message(logger, "  ERROR - File not found in S3")
        
      rescue => e
        error_count += 1
        puts "  ❌ Error: #{e.message}"
        log_message(logger, "  ERROR - #{e.message}")
      end
      
      puts ""
      
        # Reduced sleep only every 50 operations to improve performance
        sleep(0.01) if total_count % 50 == 0 && !dry_run
      end
    end
    
    end_time = Time.now
    elapsed_time = (end_time - start_time).round(2)
    files_per_second = elapsed_time > 0 ? (total_count / elapsed_time).round(2) : 0
    
    puts "=" * 50
    puts "Processing complete!"
    puts "Total files processed: #{total_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "Successful updates: #{success_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "Failed updates: #{error_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "Time elapsed: #{elapsed_time}s"
    puts "Files per second: #{files_per_second}"
    puts "Success rate: #{total_count > 0 ? (success_count.to_f / total_count * 100).round(2) : 'N/A'}%"
    
    # Estimate time for full run if this was a dry run
    if dry_run && defined?(total_files) && total_files
      estimated_full_time = (total_files * elapsed_time / total_count).round(0)
      estimated_hours = estimated_full_time / 3600
      estimated_minutes = (estimated_full_time % 3600) / 60
      puts "Estimated time for full run: #{estimated_hours}h #{estimated_minutes}m"
      log_message(logger, "Estimated time for full run: #{estimated_hours}h #{estimated_minutes}m")
    end
    
    puts "🎉 All done!"
    puts "Log saved to: #{log_file}"
    
    # Final log entries
    log_message(logger, "=" * 50)
    log_message(logger, "S3 metadata fix completed at #{Time.now}")
    log_message(logger, "Total files processed: #{total_count}")
    log_message(logger, "Successful updates: #{success_count}")
    log_message(logger, "Failed updates: #{error_count}")
    log_message(logger, "Success rate: #{total_count > 0 ? (success_count.to_f / total_count * 100).round(2) : 'N/A'}%")
    
    logger.close
  end
end

# Run the script
FixExistingS3Files.run