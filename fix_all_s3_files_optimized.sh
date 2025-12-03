#!/bin/bash

# Ensure output is not buffered
exec 1> >(stdbuf -o0 cat)
exec 2> >(stdbuf -o0 cat)

# Optimized S3 Content-Disposition Fix Script
# This version uses parallel processing for much better performance
# Usage (Environment Variables): BUCKET=bucket-name RAILS_ENV=environment [DRY_RUN=true] ./fix_all_s3_files_optimized.sh
# Usage (Command Line): ./fix_all_s3_files_optimized.sh [--dry-run] --rails-env RAILS_ENVIRONMENT --bucket BUCKET_NAME [--aws-key KEY] [--aws-secret SECRET] [--aws-region REGION]

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

# Set up logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/s3_metadata_fix_optimized_${TIMESTAMP}.log"

# Function to log messages to both console and file with immediate flushing
log_message() {
  echo "$1" | tee -a "$LOG_FILE"
  sync
}

echo "🚀 OPTIMIZED S3 Content-Disposition Fix"
echo "======================================="
if [ "$DRY_RUN" = true ]; then
  echo "🔍 DRY RUN MODE - No changes will be made"
  echo "📝 Processing only 5 files as sample"
else
  echo "⚡ LIVE MODE - Parallel processing enabled"
fi

echo "Bucket: $BUCKET"
echo "Environment: $RAILS_ENV"
echo "AWS Region: ${AWS_DEFAULT_REGION:-'default'}"
echo "AWS Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
echo "Log file: $LOG_FILE"
echo "======================================="
echo ""

# Navigate to Rails app
cd /var/www/decidim/current

# Initial log entry
log_message "$(date): Optimized S3 metadata fix started"
log_message "Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE")"
log_message "Bucket: $BUCKET"
log_message "Environment: $RAILS_ENV"

# Generate file list efficiently
echo "📊 Generating file list..."
if [ "$DRY_RUN" = true ]; then
  LIMIT_CLAUSE=".limit(5)"
else
  LIMIT_CLAUSE=""
  echo "Getting total file count..."
  TOTAL_FILES=$(RAILS_ENV=$RAILS_ENV bin/rails runner "puts ActiveStorage::Blob.count" 2>/dev/null | tail -1)
  echo "Total files in database: $(printf "%'d" $TOTAL_FILES)"
fi

RAILS_ENV=$RAILS_ENV bin/rails runner "
batch_size = 5000
current_count = 0

ActiveStorage::Blob${LIMIT_CLAUSE}.find_in_batches(batch_size: batch_size) do |batch|
  batch.each do |blob|
    current_count += 1
    puts \"#{blob.key}|#{blob.filename.sanitized}|#{blob.content_type}\"
  end
  print \"\\rExporting: #{current_count} files...\" if current_count % 1000 == 0
end
puts \"\\nExport complete: #{current_count} files\"
" > /tmp/blob_metadata_optimized.txt 2>/dev/null

TOTAL_LINES=$(wc -l < /tmp/blob_metadata_optimized.txt)
echo "✅ File list generated: $(printf "%'d" $TOTAL_LINES) files"
echo ""

# Processing variables
TOTAL_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0
START_TIME=$(date +%s)
BATCH_SIZE=500  # Much larger batches for maximum performance
MAX_PARALLEL=200  # Maximum parallel processes

# Function to process files with high parallelism
process_batch() {
  local batch_files=("$@")
  local temp_success="/tmp/batch_success_$$"
  local temp_errors="/tmp/batch_errors_$$"
  local active_jobs=0
  
  > "$temp_success"
  > "$temp_errors"
  
  for file_info in "${batch_files[@]}"; do
    if [ -z "$file_info" ]; then continue; fi
    
    # Limit concurrent processes to avoid overwhelming the system
    while [ $active_jobs -ge $MAX_PARALLEL ]; do
      sleep 0.01
      active_jobs=$(jobs -r | wc -l)
    done
    
    # Process in background with optimized AWS call
    (
      IFS='|' read -r key filename content_type <<< "$file_info"
      
      # Escape filename for shell safety
      safe_filename=$(printf '%s\n' "$filename" | sed 's/[[\.*^$()+?{|]/\\&/g')
      
      if [[ "$content_type" =~ ^image/ ]]; then
        disposition="inline"
      else
        disposition="attachment"
      fi
      
      # Use more efficient AWS CLI with reduced output
      if aws s3api copy-object \
        --bucket "$BUCKET" \
        --copy-source "$BUCKET/$key" \
        --key "$key" \
        --content-type "$content_type" \
        --content-disposition "$disposition; filename=\"$safe_filename\"" \
        --metadata-directive REPLACE \
        --no-cli-pager \
        --output text \
        --query 'CopyObjectResult.ETag' >/dev/null 2>&1; then
        echo "1" >> "$temp_success"
      else
        echo "$filename" >> "$temp_errors"
      fi
    ) &
    
    active_jobs=$((active_jobs + 1))
  done
  
  # Wait for all background processes to complete
  wait
  
  # Count results
  local success_count=$(wc -l < "$temp_success" 2>/dev/null || echo "0")
  local error_count=$(wc -l < "$temp_errors" 2>/dev/null || echo "0")
  
  echo "$success_count|$error_count"
  
  rm -f "$temp_success" "$temp_errors"
}

echo "🚀 Starting processing..."
BATCH_FILES=()
CURRENT_BATCH=0

while IFS='|' read -r key filename content_type; do
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  
  if [ "$DRY_RUN" = true ]; then
    # Dry run - show details for each file
    if [[ "$content_type" =~ ^image/ ]]; then
      disposition="inline"
    else
      disposition="attachment"
    fi
    
    echo "[$TOTAL_COUNT/$TOTAL_LINES] 📄 $filename"
    echo "  Content-Type: $content_type"
    echo "  Content-Disposition: $disposition; filename=\"$filename\""
    echo ""
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    # Live mode - batch processing
    BATCH_FILES+=("$key|$filename|$content_type")
    
    if [ ${#BATCH_FILES[@]} -eq $BATCH_SIZE ]; then
      CURRENT_BATCH=$((CURRENT_BATCH + 1))
      FILES_PROCESSED=$((CURRENT_BATCH * BATCH_SIZE))
      
      # Show progress more frequently for better feedback
      ELAPSED=$(($(date +%s) - START_TIME))
      RATE=$((FILES_PROCESSED / (ELAPSED + 1)))
      PERCENT=$((FILES_PROCESSED * 100 / TOTAL_LINES))
      
      printf "\r⚡ [%d%%] %s/%s files (%s/sec) [Batch %d] " \
        "$PERCENT" \
        "$(printf "%'d" $FILES_PROCESSED)" \
        "$(printf "%'d" $TOTAL_LINES)" \
        "$(printf "%'d" $RATE)" \
        "$CURRENT_BATCH"
      
      # Process batch with high parallelism
      RESULT=$(process_batch "${BATCH_FILES[@]}")
      IFS='|' read -r batch_success batch_errors <<< "$RESULT"
      
      SUCCESS_COUNT=$((SUCCESS_COUNT + batch_success))
      ERROR_COUNT=$((ERROR_COUNT + batch_errors))
      
      # Show milestone every 20 batches for more frequent updates
      if [ $((CURRENT_BATCH % 20)) -eq 0 ]; then
        echo ""
        REMAINING_FILES=$((TOTAL_LINES - FILES_PROCESSED))
        ETA_SECONDS=$((REMAINING_FILES / (RATE + 1)))
        ETA_MINUTES=$((ETA_SECONDS / 60))
        
        echo "✨ Milestone: $(printf "%'d" $FILES_PROCESSED) files processed"
        echo "   Rate: $(printf "%'d" $RATE) files/sec | Success: $(printf "%'d" $SUCCESS_COUNT) | Errors: $(printf "%'d" $ERROR_COUNT)"
        echo "   ETA: ~${ETA_MINUTES} minutes remaining"
        log_message "Milestone: $(printf "%'d" $FILES_PROCESSED) files ($(printf "%'d" $RATE) files/sec)"
      fi
      
      BATCH_FILES=()
    fi
  fi
done < /tmp/blob_metadata_optimized.txt

# Process remaining files in final batch (live mode)
if [ "$DRY_RUN" != true ] && [ ${#BATCH_FILES[@]} -gt 0 ]; then
  echo ""
  echo "Processing final batch of ${#BATCH_FILES[@]} files..."
  RESULT=$(process_batch "${BATCH_FILES[@]}")
  IFS='|' read -r batch_success batch_errors <<< "$RESULT"
  SUCCESS_COUNT=$((SUCCESS_COUNT + batch_success))
  ERROR_COUNT=$((ERROR_COUNT + batch_errors))
fi

echo ""
echo "========================================"
echo "🎉 Processing Complete!"
echo "========================================"

END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
FILES_PER_SECOND=$((TOTAL_COUNT / (ELAPSED_TIME + 1)))

echo "📊 Results:"
echo "  Total files processed: $(printf "%'d" $TOTAL_COUNT)"
echo "  Successful updates: $(printf "%'d" $SUCCESS_COUNT)"
echo "  Failed updates: $(printf "%'d" $ERROR_COUNT)"
echo "  Time elapsed: ${ELAPSED_TIME}s"
echo "  Processing rate: $(printf "%'d" $FILES_PER_SECOND) files/second"
if [ $TOTAL_COUNT -gt 0 ]; then
  SUCCESS_RATE=$(( (SUCCESS_COUNT * 100) / TOTAL_COUNT ))
  echo "  Success rate: ${SUCCESS_RATE}%"
fi

if [ "$DRY_RUN" = true ] && [ -n "$TOTAL_FILES" ]; then
  ESTIMATED_TIME=$((TOTAL_FILES * ELAPSED_TIME / TOTAL_COUNT))
  ESTIMATED_HOURS=$((ESTIMATED_TIME / 3600))
  ESTIMATED_MINUTES=$(( (ESTIMATED_TIME % 3600) / 60 ))
  echo ""
  echo "📈 Estimated time for full run: ${ESTIMATED_HOURS}h ${ESTIMATED_MINUTES}m"
  echo "   At current rate of $(printf "%'d" $FILES_PER_SECOND) files/second"
fi

echo ""
echo "📄 Log file: $LOG_FILE"

# Final log entries
log_message "========================================"
log_message "$(date): Optimized S3 metadata fix completed"
log_message "Total files processed: $(printf "%'d" $TOTAL_COUNT)"
log_message "Successful updates: $(printf "%'d" $SUCCESS_COUNT)"
log_message "Failed updates: $(printf "%'d" $ERROR_COUNT)"
log_message "Processing rate: $(printf "%'d" $FILES_PER_SECOND) files/second"
if [ $TOTAL_COUNT -gt 0 ]; then
  log_message "Success rate: $(( (SUCCESS_COUNT * 100) / TOTAL_COUNT ))%"
fi

# Cleanup
rm -f /tmp/blob_metadata_optimized.txt

echo "🚀 Optimization complete! Use this script for much better performance."