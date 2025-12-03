#!/bin/bash

# TURBO MODE S3 Content-Disposition Fix Script
# This version uses AWS CLI's built-in parallelism for maximum speed
# Usage: ./fix_all_s3_files_turbo.sh --bucket BUCKET --rails-env ENV --aws-key KEY --aws-secret SECRET --aws-region REGION

set -e

# Initialize variables (no defaults, all must be provided)
BUCKET=""
RAILS_ENV=""
DRY_RUN=false
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_DEFAULT_REGION=""

# Parse command line arguments - all required
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --rails-env) RAILS_ENV="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    --aws-key) AWS_ACCESS_KEY_ID="$2"; shift 2 ;;
    --aws-secret) AWS_SECRET_ACCESS_KEY="$2"; shift 2 ;;
    --aws-region) AWS_DEFAULT_REGION="$2"; shift 2 ;;
    *) 
      echo "Unknown option: $1"
      echo "Usage: $0 --bucket BUCKET --rails-env ENVIRONMENT --aws-key KEY --aws-secret SECRET --aws-region REGION [--dry-run]"
      exit 1 
      ;;
  esac
done

# Validate all required arguments
if [ -z "$RAILS_ENV" ] || [ -z "$BUCKET" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_DEFAULT_REGION" ]; then
  echo "❌ Missing required arguments"
  echo ""
  echo "Usage: $0 --bucket BUCKET --rails-env ENVIRONMENT --aws-key KEY --aws-secret SECRET --aws-region REGION [--dry-run]"
  echo ""
  echo "Required arguments:"
  echo "  --bucket BUCKET        S3 bucket name"
  echo "  --rails-env ENV        Rails environment (staging, production)"
  echo "  --aws-key KEY          AWS Access Key ID"
  echo "  --aws-secret SECRET    AWS Secret Access Key"
  echo "  --aws-region REGION    AWS region (e.g., eu-south-2)"
  echo ""
  echo "Optional arguments:"
  echo "  --dry-run              Show what would be done without making changes"
  echo ""
  echo "Example:"
  echo "  $0 --bucket your-bucket-name --rails-env staging --aws-key AKIA... --aws-secret ... --aws-region eu-south-2"
  exit 1
fi

# Export AWS credentials for AWS CLI
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

echo "🚀 TURBO MODE S3 Fix"
echo "==================="
echo "Bucket: $BUCKET"
echo "Environment: $RAILS_ENV"
echo "AWS Region: $AWS_DEFAULT_REGION"
echo "AWS Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
echo "Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE")"
echo ""

cd /var/www/decidim/current

# Generate optimized script for parallel processing
echo "📊 Generating processing commands..."

TEMP_SCRIPT="/tmp/s3_turbo_commands_$$.sh"
cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash
key="$1"
filename="$2"
content_type="$3"
bucket="$4"

# Determine disposition
if [[ "$content_type" =~ ^image/ ]]; then
  disposition="inline"
else
  disposition="attachment"
fi

# Execute AWS command with optimized settings
aws s3api copy-object \
  --bucket "$bucket" \
  --copy-source "$bucket/$key" \
  --key "$key" \
  --content-type "$content_type" \
  --content-disposition "$disposition; filename=\"$filename\"" \
  --metadata-directive REPLACE \
  --no-cli-pager \
  --output text \
  --query 'CopyObjectResult.ETag' 2>/dev/null && echo "✅" || echo "❌"
EOF

chmod +x "$TEMP_SCRIPT"

# Generate file list and process with GNU parallel or xargs
RAILS_ENV=$RAILS_ENV bin/rails runner "
ActiveStorage::Blob.find_each(batch_size: 5000) do |blob|
  puts \"#{blob.key}|#{blob.filename.sanitized}|#{blob.content_type}\"
end
" | if [ "$DRY_RUN" = "true" ]; then
  head -5 | while IFS='|' read -r key filename content_type; do
    echo "🔍 Would process: $filename"
    echo "   Key: $key"
    echo "   Content-Type: $content_type"
    echo ""
  done
else
  echo "🚀 Starting TURBO processing with maximum parallelism..."
  start_time=$(date +%s)
  
  # Use GNU parallel if available, otherwise xargs with high parallelism
  if command -v parallel >/dev/null 2>&1; then
    echo "Using GNU Parallel for maximum speed..."
    parallel -j 300 --colsep '|' "$TEMP_SCRIPT" {1} {2} {3} "$BUCKET"
  else
    echo "Using xargs with high parallelism..."
    # Process 300 files simultaneously with xargs
    xargs -n 1 -P 300 -I {} bash -c '
      IFS="|" read -r key filename content_type <<< "{}"
      if [[ "$content_type" =~ ^image/ ]]; then
        disposition="inline"
      else
        disposition="attachment"
      fi
      aws s3api copy-object \
        --bucket "'$BUCKET'" \
        --copy-source "'$BUCKET'/$key" \
        --key "$key" \
        --content-type "$content_type" \
        --content-disposition "$disposition; filename=\"$filename\"" \
        --metadata-directive REPLACE \
        --no-cli-pager \
        --output text >/dev/null 2>&1 && echo "✅ $filename" || echo "❌ $filename"
    '
  fi
  
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  echo ""
  echo "🎉 TURBO processing complete in ${elapsed} seconds!"
fi

# Cleanup
rm -f "$TEMP_SCRIPT"

echo "✨ Done!"