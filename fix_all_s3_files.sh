#!/bin/bash

# Ensure output is not buffered
exec 1> >(stdbuf -o0 cat)
exec 2> >(stdbuf -o0 cat)

# Script to fix all S3 objects with correct Content-Disposition and Content-Type
# Usage (Environment Variables): BUCKET=bucket-name RAILS_ENV=environment [DRY_RUN=true] ./fix_all_s3_files.sh
# Usage (Command Line): ./fix_all_s3_files.sh [--dry-run] --rails-env RAILS_ENVIRONMENT --bucket BUCKET_NAME [--aws-key KEY] [--aws-secret SECRET] [--aws-region REGION]
# 
# Environment Variables (alternative to command line):
#   BUCKET=bucket-name               S3 bucket name (REQUIRED)
#   RAILS_ENV=environment            Rails environment (REQUIRED)  
#   DRY_RUN=true                     Show what would be done without making changes (processes only 5 files as sample)
#   AWS_ACCESS_KEY_ID=...            AWS Access Key ID
#   AWS_SECRET_ACCESS_KEY=...        AWS Secret Access Key
#   AWS_DEFAULT_REGION=...           AWS Region
#
# Command Line Options (override environment variables):
#   --dry-run                        Show what would be done without making changes
#   --rails-env RAILS_ENVIRONMENT   Rails environment (REQUIRED)
#   --bucket BUCKET_NAME             S3 bucket name (REQUIRED)
#   --aws-key AWS_ACCESS_KEY_ID      AWS Access Key ID
#   --aws-secret AWS_SECRET_KEY      AWS Secret Access Key
#   --aws-region AWS_REGION          AWS Region
#
# Examples:
#   BUCKET=your-bucket-name RAILS_ENV=staging DRY_RUN=true ./fix_all_s3_files.sh
#   ./fix_all_s3_files.sh --bucket your-bucket-name --rails-env staging --dry-run

set -e

# Initialize variables from environment variables first
BUCKET="${BUCKET:-}"
RAILS_ENV="${RAILS_ENV:-}"
DRY_RUN="${DRY_RUN:-false}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-}"

# Parse command line arguments (these override environment variables)
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --rails-env)
      RAILS_ENV="$2"
      shift 2
      ;;
    --bucket)
      BUCKET="$2"
      shift 2
      ;;
    --aws-key)
      AWS_ACCESS_KEY_ID="$2"
      shift 2
      ;;
    --aws-secret)
      AWS_SECRET_ACCESS_KEY="$2"
      shift 2
      ;;
    --aws-region)
      AWS_DEFAULT_REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] --rails-env RAILS_ENVIRONMENT --bucket BUCKET_NAME [--aws-key KEY] [--aws-secret SECRET] [--aws-region REGION]"
      echo "Or use environment variables: BUCKET=bucket-name RAILS_ENV=environment [DRY_RUN=true] $0"
      exit 1
      ;;
  esac
done

# Convert DRY_RUN to boolean for consistency
if [ "$DRY_RUN" = "true" ]; then
  DRY_RUN=true
else
  DRY_RUN=false
fi

# Validate required arguments
if [ -z "$RAILS_ENV" ] || [ -z "$BUCKET" ]; then
  echo "❌ Error: Missing required arguments"
  echo ""
  echo "Usage (Environment Variables):"
  echo "  BUCKET=bucket-name RAILS_ENV=environment [DRY_RUN=true] $0"
  echo ""
  echo "Usage (Command Line):"
  echo "  $0 [--dry-run] --rails-env RAILS_ENVIRONMENT --bucket BUCKET_NAME [--aws-key KEY] [--aws-secret SECRET] [--aws-region REGION]"
  echo ""
  echo "Required arguments:"
  echo "  BUCKET / --bucket BUCKET_NAME           S3 bucket name"
  echo "  RAILS_ENV / --rails-env ENVIRONMENT     Rails environment (e.g., staging, production)"
  echo ""
  echo "Optional arguments:"
  echo "  DRY_RUN=true / --dry-run                Show what would be done without making changes"
  echo "  AWS_ACCESS_KEY_ID / --aws-key           AWS Access Key ID"
  echo "  AWS_SECRET_ACCESS_KEY / --aws-secret    AWS Secret Access Key"
  echo "  AWS_DEFAULT_REGION / --aws-region       AWS Region"
  echo ""
  echo "Examples:"
  echo "  BUCKET=your-bucket-name RAILS_ENV=staging DRY_RUN=true $0"
  echo "  $0 --bucket your-bucket-name --rails-env staging --dry-run"
  exit 1
fi

# Validate AWS credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "❌ Error: AWS credentials are required"
  echo "Please provide AWS credentials using one of these methods:"
  echo "1. Command line: --aws-key YOUR_KEY --aws-secret YOUR_SECRET"
  echo "2. Environment variables: export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
  echo "3. AWS CLI profile: aws configure"
  exit 1
fi

# Export AWS credentials for aws cli
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
if [ -n "$AWS_DEFAULT_REGION" ]; then
  export AWS_DEFAULT_REGION
fi

if [ "$DRY_RUN" = true ]; then
  echo "🔍 DRY RUN MODE - No changes will be made"
  echo "📝 Processing only 5 files as sample"
else
  echo "🚀 LIVE MODE - Changes will be applied"
fi

# Set up logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/s3_metadata_fix_${TIMESTAMP}.log"

echo "Starting S3 metadata fix..."
echo "Bucket: $BUCKET"
echo "Environment: $RAILS_ENV"
echo "AWS Region: ${AWS_DEFAULT_REGION:-'default'}"
echo "AWS Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
echo "Log file: $LOG_FILE"
echo "=================================="

# Function to log messages to both console and file with immediate flushing
log_message() {
  echo "$1" | tee -a "$LOG_FILE"
  # Force flush
  sync
}

# Function to show progress with immediate output
show_progress() {
  local current=$1
  local total=$2
  local percent=$((current * 100 / total))
  local progress_bar=""
  local filled=$((percent / 2))
  
  for ((i=0; i<50; i++)); do
    if [ $i -lt $filled ]; then
      progress_bar+="█"
    else
      progress_bar+=" "
    fi
  done
  
  printf "\r[%s] %d%% (%d/%d)" "$progress_bar" "$percent" "$current" "$total"
  # Force immediate output
  printf "" >&1
}

# Initial log entry
log_message "$(date): S3 metadata fix started"
log_message "Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE")"
log_message "Bucket: $BUCKET"
log_message "Environment: $RAILS_ENV"
log_message "==============================================="

# Get all blob keys and their metadata from Rails
cd /var/www/decidim/current

if [ "$DRY_RUN" = true ]; then
  LIMIT_CLAUSE=".limit(5)"
  log_message "DRY RUN: Processing only 5 files as sample"
else
  LIMIT_CLAUSE=""
  log_message "Getting total file count..."
  TOTAL_FILES=$(RAILS_ENV=$RAILS_ENV bin/rails runner "puts ActiveStorage::Blob.count")
  log_message "Total files in database: $TOTAL_FILES"
fi

log_message "Generating file list..."
RAILS_ENV=$RAILS_ENV bin/rails runner "
require 'json'
puts 'Starting batch export...'
batch_size = 1000
total_batches = (ActiveStorage::Blob.count / batch_size.to_f).ceil
current_batch = 0

ActiveStorage::Blob${LIMIT_CLAUSE}.find_in_batches(batch_size: batch_size) do |batch|
  current_batch += 1
  puts \"Processing batch #{current_batch}/#{total_batches}\" if current_batch % 10 == 0
  
  batch.each do |blob|
    puts \"#{blob.key}|#{blob.filename.sanitized}|#{blob.content_type}\"
  end
end
" > /tmp/blob_metadata.txt
log_message "File list generated"

# Read the file and process each blob
TOTAL_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0
START_TIME=$(date +%s)

# Get total lines for progress tracking (excluding header)
if [ "$DRY_RUN" != true ]; then
  TOTAL_LINES=$(($(wc -l < /tmp/blob_metadata.txt) - 1))
else
  TOTAL_LINES=5
fi

while IFS='|' read -r key filename content_type; do
  # Skip header line
  if [ "$key" = "key" ]; then
    continue
  fi
  
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  
  # Show progress every 10 files for dry run, 100 for live mode
  if [ "$DRY_RUN" = true ]; then
    show_progress $TOTAL_COUNT $TOTAL_LINES
    echo ""
    echo "[$TOTAL_COUNT/$TOTAL_LINES] Processing: $filename"
  elif [ $((TOTAL_COUNT % 100)) -eq 0 ] || [ $TOTAL_COUNT -eq 1 ]; then
    show_progress $TOTAL_COUNT $TOTAL_LINES
  fi
  
  # Log detailed info every 1000 files or for dry run
  if [ "$DRY_RUN" = true ] || [ $((TOTAL_COUNT % 1000)) -eq 0 ] || [ $TOTAL_COUNT -eq 1 ]; then
    if [ "$DRY_RUN" != true ]; then
      echo ""
      echo "Processing: $filename ($key)"
    fi
    log_message "$(date): Processing file $TOTAL_COUNT/$TOTAL_LINES - $filename (key: $key)"
  fi
  
  # Determine content disposition based on content type
  if [[ "$content_type" =~ ^image/ ]]; then
    disposition="inline"
  else
    disposition="attachment"
  fi
  
  # Update S3 object metadata (or simulate in dry-run)
  if [ "$DRY_RUN" = true ]; then
    echo "  🔍 Would update with:"
    echo "    Content-Type: $content_type"
    echo "    Content-Disposition: $disposition; filename=\"$filename\""
    log_message "  DRY RUN - Would set Content-Type: $content_type, Content-Disposition: $disposition; filename=\"$filename\""
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    # Show a heartbeat every 10 files to indicate activity
    if [ $((TOTAL_COUNT % 10)) -eq 0 ]; then
      printf "."
    fi
    
    if aws s3api copy-object \
      --bucket "$BUCKET" \
      --copy-source "$BUCKET/$key" \
      --key "$key" \
      --content-type "$content_type" \
      --content-disposition "$disposition; filename=\"$filename\"" \
      --metadata-directive REPLACE \
      > /dev/null 2>&1; then
      
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      if [ $((TOTAL_COUNT % 1000)) -eq 0 ]; then
        echo "  ✓ Success: $filename"
        log_message "  SUCCESS - Updated metadata for $filename"
      fi
    else
      ERROR_COUNT=$((ERROR_COUNT + 1))
      echo "  ✗ Failed: $filename"
      log_message "  ERROR - Failed to update metadata for $filename"
    fi
  fi
  
  # Reduced delay for large volumes, but still avoid rate limits
  if [ $((TOTAL_COUNT % 50)) -eq 0 ]; then
    sleep 0.1
  fi
  
while IFS= read -r line; do
  # Skip empty lines
  if [ -z "$line" ]; then continue; fi
  
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  
  if [ "$DRY_RUN" = true ]; then
    # For dry run, process immediately with full output
    IFS='|' read -r key filename content_type <<< "$line"
    
    if [[ "$content_type" =~ ^image/ ]]; then
      disposition="inline"
    else
      disposition="attachment"
    fi
    
    echo "[$TOTAL_COUNT/$TOTAL_LINES] Processing: $filename"
    echo "  🔍 Would update with:"
    echo "    Content-Type: $content_type"
    echo "    Content-Disposition: $disposition; filename=\"$filename\""
    echo ""
    
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    log_message "DRY RUN - File $TOTAL_COUNT: $filename (Content-Type: $content_type)"
  else
    # For live run, batch process for speed
    BATCH_FILES+=("$line")
    
    # Process batch when it's full
    if [ ${#BATCH_FILES[@]} -eq $BATCH_SIZE ]; then
      CURRENT_BATCH=$((CURRENT_BATCH + 1))
      
      # Show progress
      ELAPSED=$(($(date +%s) - START_BATCH_TIME))
      FILES_PROCESSED=$((CURRENT_BATCH * BATCH_SIZE))
      RATE=$(( FILES_PROCESSED / (ELAPSED + 1) ))
      
      printf "\r[$FILES_PROCESSED/$TOTAL_LINES] Batch $CURRENT_BATCH (${RATE}/sec) "
      
      # Show heartbeat every 10 batches
      if [ $((CURRENT_BATCH % 10)) -eq 0 ]; then
        printf "."
      fi
      
      # Process the batch
      process_batch "${BATCH_FILES[@]}" 2>/tmp/batch_errors.log
      
      # Count results from this batch
      SUCCESS_COUNT=$((SUCCESS_COUNT + BATCH_SIZE))
      
      # Log major progress milestones
      if [ $((CURRENT_BATCH % 100)) -eq 0 ]; then
        echo ""
        echo "Milestone: Processed $FILES_PROCESSED files in ${ELAPSED}s (${RATE} files/sec)"
        log_message "Milestone: $FILES_PROCESSED files processed, ${SUCCESS_COUNT} successful"
      fi
      
      # Clear batch
      BATCH_FILES=()
    fi
  fi

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
FILES_PER_SECOND=$([ $ELAPSED_TIME -gt 0 ] && echo "scale=2; $TOTAL_COUNT / $ELAPSED_TIME" | bc || echo "N/A")

echo ""
echo "=================================="
echo "Processing complete!"
echo "Total files: $TOTAL_COUNT"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $ERROR_COUNT"
echo "Time elapsed: ${ELAPSED_TIME}s"
echo "Files per second: $FILES_PER_SECOND"

# Estimate time for full run if this was a dry run
if [ "$DRY_RUN" = true ] && [ -n "$TOTAL_FILES" ]; then
  ESTIMATED_FULL_TIME=$((TOTAL_FILES * ELAPSED_TIME / TOTAL_COUNT))
  ESTIMATED_HOURS=$((ESTIMATED_FULL_TIME / 3600))
  ESTIMATED_MINUTES=$(((ESTIMATED_FULL_TIME % 3600) / 60))
  echo "Estimated time for full run: ${ESTIMATED_HOURS}h ${ESTIMATED_MINUTES}m"
fi

# Final log entries
log_message "==============================================="
log_message "$(date): S3 metadata fix completed"
log_message "Total files processed: $TOTAL_COUNT"
log_message "Successful updates: $SUCCESS_COUNT"
log_message "Failed updates: $ERROR_COUNT"
log_message "Success rate: $([ $TOTAL_COUNT -gt 0 ] && echo "scale=2; $SUCCESS_COUNT * 100 / $TOTAL_COUNT" | bc || echo "N/A")%"

# Cleanup
rm -f /tmp/blob_metadata.txt

echo "Log saved to: $LOG_FILE"
echo "All done! 🎉"