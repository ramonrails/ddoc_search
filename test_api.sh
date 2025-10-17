#!/bin/bash

# API Testing Script for DDoc Search
# This script demonstrates all available API endpoints with real examples
# It will set up a fresh test environment with database, tenant, and API key

set -e  # Exit on any error

BASE_URL="http://localhost:3000"

echo "=========================================="
echo "Setting up Test Environment"
echo "=========================================="
echo ""

# Step 1: Drop the existing test database
echo "1. Dropping existing test database..."
RAILS_ENV=test rails db:drop 2>/dev/null || echo "No existing test database to drop"
echo "   ✓ Test database dropped"
echo ""

# Step 2: Create a new test database
echo "2. Creating new test database..."
RAILS_ENV=test rails db:create
echo "   ✓ Test database created"
echo ""

# Step 3: Run migrations
echo "3. Running database migrations..."
RAILS_ENV=test rails db:migrate
echo "   ✓ Migrations completed"
echo ""

# Step 4: Create a test tenant and capture the API key
echo "4. Creating test tenant..."
TENANT_OUTPUT=$(RAILS_ENV=test rails runner "
tenant = Tenant.create!(
  name: 'Test Company',
  subdomain: 'test',
  document_quota: 10000,
  rate_limit_per_minute: 100
)
puts tenant.api_key
")

# Extract the API key from the output (last line)
API_KEY=$(echo "$TENANT_OUTPUT" | tail -n 1)

if [ -z "$API_KEY" ]; then
  echo "   ✗ Failed to create tenant or retrieve API key"
  exit 1
fi

echo "   ✓ Tenant created successfully"
echo "   ✓ API Key: $API_KEY"
echo ""

# Step 5: Save API key to .env.test for future use
echo "5. Saving API key to .env.test..."
echo "TEST_API_KEY=$API_KEY" > .env.test
echo "   ✓ API key saved to .env.test"
echo ""

echo "=========================================="
echo "Test Environment Setup Complete!"
echo "=========================================="
echo ""
echo "Starting Rails server if not already running..."
echo "Please ensure the server is running with: RAILS_ENV=test rails server"
echo ""
echo "Press Enter to continue with API tests..."
read

# Export the API key for use in the tests below
export TEST_API_KEY="$API_KEY"

echo "=========================================="
echo "DDoc Search API Test Suite"
echo "=========================================="
echo ""

# 1. Health Check
echo "1. Testing Health Check..."
curl -s "$BASE_URL/health" | jq '.'
echo ""
echo ""

# 2. Create Documents from test files
echo "2. Creating Documents..."
echo ""

echo "Creating document from car.txt..."
DOC1=$(curl -s -X POST "$BASE_URL/v1/documents" \
  -H "X-API-Key: $TEST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "The Mysterious Garage - Classic Cars Story",
      "content": "'"$(cat test/fixtures/files/car.txt | tr '\n' ' ' | sed 's/"/\\"/g')"'",
      "metadata": {"category": "story", "tags": ["cars", "nostalgia", "family"]}
    }
  }')
echo "$DOC1" | jq '.'
DOC1_ID=$(echo "$DOC1" | jq -r '.data.id')
echo ""

echo "Creating document from earth.txt..."
DOC2=$(curl -s -X POST "$BASE_URL/v1/documents" \
  -H "X-API-Key: $TEST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "The Symphony of Earth - Nature Poetry",
      "content": "'"$(cat test/fixtures/files/earth.txt | tr '\n' ' ' | sed 's/"/\\"/g')"'",
      "metadata": {"category": "poetry", "tags": ["nature", "earth", "environment"]}
    }
  }')
echo "$DOC2" | jq '.'
DOC2_ID=$(echo "$DOC2" | jq -r '.data.id')
echo ""

echo "Creating document from environment.txt..."
DOC3=$(curl -s -X POST "$BASE_URL/v1/documents" \
  -H "X-API-Key: $TEST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "The Weight of Wheels - Environmental Impact",
      "content": "'"$(cat test/fixtures/files/environment.txt | tr '\n' ' ' | sed 's/"/\\"/g')"'",
      "metadata": {"category": "article", "tags": ["environment", "cars", "sustainability"]}
    }
  }')
echo "$DOC3" | jq '.'
DOC3_ID=$(echo "$DOC3" | jq -r '.data.id')
echo ""

# Wait for indexing
echo "Waiting 2 seconds for Elasticsearch indexing..."
sleep 2
echo ""

# 3. Retrieve a Document
echo "3. Retrieving Document $DOC1_ID..."
curl -s "$BASE_URL/v1/documents/$DOC1_ID" \
  -H "X-API-Key: $TEST_API_KEY" | jq '.'
echo ""
echo ""

# 4. Search Documents
echo "4. Searching Documents..."
echo ""

echo "Search for 'car'..."
curl -s "$BASE_URL/v1/search?q=car&page=1&per_page=10" \
  -H "X-API-Key: $TEST_API_KEY" | jq '.'
echo ""

echo "Search for 'earth environment'..."
curl -s "$BASE_URL/v1/search?q=earth+environment&page=1&per_page=10" \
  -H "X-API-Key: $TEST_API_KEY" | jq '.'
echo ""

echo "Search for 'nature'..."
curl -s "$BASE_URL/v1/search?q=nature&page=1&per_page=10" \
  -H "X-API-Key: $TEST_API_KEY" | jq '.'
echo ""

# 5. Delete a Document
echo "5. Deleting Document $DOC2_ID..."
curl -s -X DELETE "$BASE_URL/v1/documents/$DOC2_ID" \
  -H "X-API-Key: $TEST_API_KEY" | jq '.'
echo ""
echo ""

echo "=========================================="
echo "API Test Suite Completed!"
echo "=========================================="
