# DDoc Search

A high-performance, multi-tenant document search API built with Ruby on Rails. This application provides full-text search capabilities powered by Weaviate, with support for tenant isolation, rate limiting, caching, and asynchronous document indexing via Kafka.

## Quick Start

### Running Locally

1. **Install dependencies**

   ```bash
   bundle install
   ```

2. **Start required services** (Weaviate, Redis, Kafka)

   ```bash
   docker compose -f docker-compose.dev.yml up -d
   ```

3. **Setup database and Weaviate**

   ```bash
   rails db:drop 
   rails db:create 
   rails db:migrate
   rails runner "Document.ensure_weaviate_schema!"
   ```

4. **Create a test tenant**

   ```bash
   rails runner tmp/create_tenant.rb
   # Save the API key from the output!
   ```

5. **Start Rails server**

   ```bash
   rails server -p 3000
   ```

6. **Test the API** - Use the provided `test_api.sh` script with real test files:

   ```bash
   chmod +x test_api.sh
   ./test_api.sh
   ```

### Ready-to-Use curl Commands

Using test API key: `aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe`

**Health Check:**

```bash
curl http://localhost:3000/health | jq '.'
```

**Create Document from test/fixtures/files/car.txt:**

```bash
curl -X POST http://localhost:3000/v1/documents \
  -H "X-API-Key: aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "The Mysterious Garage - Classic Cars Story",
      "content": "'"$(cat test/fixtures/files/car.txt | tr '\n' ' ' | sed 's/"/\\"/g')"'",
      "metadata": {"category": "story", "tags": ["cars", "nostalgia"]}
    }
  }' | jq '.'
```

```bash
curl -X POST http://localhost:3000/v1/documents \
  -H "X-API-Key: aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "The Symphony of Earth",
      "content": "'"$(cat test/fixtures/files/earth.txt | tr '\n' ' ' | sed 's/"/\\"/g')"'",
      "metadata": {"category": "story", "tags": ["earth", "life", "harmony"]}
    }
  }' | jq '.'
```

**Retrieve Document:**

```bash
curl http://localhost:3000/v1/documents/1 \
  -H "X-API-Key: aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe" | jq '.'
```

**Search Documents:**

```bash
curl "http://localhost:3000/v1/search?q=car&page=1&per_page=10" \
  -H "X-API-Key: aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe" | jq '.'
```

**Delete Document:**

```bash
curl -X DELETE http://localhost:3000/v1/documents/1 \
  -H "X-API-Key: aead1b358e37d400e37bd9f6d031fe3a0fab53f6f6e3839b494740b7373658fe" | jq '.'
```

### Test Files Available

The project includes three test files in `test/fixtures/files/` that you can use to test the API:

- **car.txt** - A story about classic cars and a mysterious garage
- **earth.txt** - A poetic description of Earth and nature
- **environment.txt** - An article about environmental impact of cars

## Overview

DDoc Search is designed to handle document storage and search for multiple tenants with the following key features:

- **Multi-tenant Architecture**: Complete data isolation per tenant with subdomain-based routing
- **Full-text Search**: Powered by Weaviate with BM25 keyword search
- **Asynchronous Processing**: Kafka-based message queue for document indexing operations
- **High Performance**: Redis caching, circuit breakers, and rate limiting
- **Scalable Design**: Horizontal scaling support with Weaviate's distributed architecture
- **RESTful API**: Clean JSON API with comprehensive error handling

## Architecture

### Technology Stack

- **Framework**: Ruby on Rails 8.0.3
- **Ruby Version**: 3.3.0 (3.4.7 for Docker)
- **Database**: SQLite3 (development/test), with support for multiple databases in production
- **Search Engine**: Weaviate 1.26.1
- **Cache**: Redis 5.0 with connection pooling
- **Message Queue**: Kafka (via Karafka 2.4)
- **Background Jobs**: Sidekiq 7.0
- **Web Server**: Puma with Thruster (production)
- **Containerization**: Docker with Kamal deployment

### Key Components

- **Tenant Middleware**: Request-level tenant identification via API keys
- **Circuit Breaker**: Prevents cascading failures to Weaviate
- **Rate Limiter**: Redis-based sliding window rate limiting per tenant
- **Document Indexing**: Async Kafka-based indexing with automatic retries
- **Search Analytics**: Background job processing for usage metrics

## API Endpoints

### Health Check

```bash
GET /health
GET /up
```

### Documents (v1)

```bash
POST   /v1/documents       # Create a new document
GET    /v1/documents/:id   # Retrieve a document
DELETE /v1/documents/:id   # Delete a document
```

### Search (v1)

```bash
GET /v1/search?q=query&page=1&per_page=20
```

All API endpoints (except health checks) require authentication via the `X-API-Key` header.

## Setup and Configuration

### Prerequisites

Ensure you have the following installed:

- Ruby 3.3.0 or higher
- Bundler 2.x
- PostgreSQL (if migrating from SQLite)
- Weaviate 1.26+
- Redis 5.0+
- Kafka (Apache Kafka or compatible)

### Installation

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd ddoc_search
   ```

2. **Install dependencies**

   ```bash
   bundle install
   ```

3. **Configure environment variables**

   Create a `.env` file in the project root:

   ```bash
   # Database
   DATABASE_URL=sqlite3:storage/development.sqlite3

   # Weaviate
   WEAVIATE_URL=http://localhost:8080

   # Redis
   REDIS_URL=redis://localhost:6379/0

   # Kafka
   KAFKA_BROKERS=localhost:9092

   # Rails
   RAILS_ENV=development
   SECRET_KEY_BASE=<generate with: rails secret>
   ```

4. **Setup the database**

   ```bash
   rails db:create
   rails db:migrate
   rails db:seed  # Optional: creates sample data
   ```

5. **Configure Weaviate**

   Ensure Weaviate is running, then create the schema:

   ```bash
   rails console
   > Document.ensure_weaviate_schema!
   ```

6. **Start required services**

   Start Redis:

   ```bash
   redis-server
   ```

   Start Kafka (if running locally):

   ```bash
   # Start Zookeeper
   zookeeper-server-start.sh config/zookeeper.properties

   # Start Kafka
   kafka-server-start.sh config/server.properties
   ```

7. **Start Karafka consumer**

   ```bash
   bundle exec karafka server
   ```

8. **Start Sidekiq**

   ```bash
   bundle exec sidekiq
   ```

9. **Start the Rails server**

   ```bash
   rails server
   ```

The application will be available at `http://localhost:3000`.

### Docker Setup

Build and run with Docker:

```bash
# Build the image
docker build -t ddoc_search .

# Run the container
docker run -d \
  -p 80:80 \
  -e RAILS_MASTER_KEY=<value from config/master.key> \
  -e WEAVIATE_URL=http://weaviate:8080 \
  -e REDIS_URL=redis://redis:6379/0 \
  -e KAFKA_BROKERS=kafka:9092 \
  --name ddoc_search \
  ddoc_search
```

Or use Kamal for deployment:

```bash
kamal setup
kamal deploy
```

## Configuration Files

### Database Configuration

- [config/database.yml](config/database.yml) - Database connection settings for all environments

### Application Configuration

- [config/initializers/weaviate.rb](config/initializers/weaviate.rb) - Weaviate client configuration
- [config/initializers/redis.rb](config/initializers/redis.rb) - Redis connection pool setup
- [config/initializers/karafka.rb](config/initializers/karafka.rb) - Kafka consumer configuration
- [config/initializers/sidekiq.rb](config/initializers/sidekiq.rb) - Sidekiq background job configuration
- [config/initializers/cors.rb](config/initializers/cors.rb) - CORS policy settings

### Deployment Configuration

- [config/deploy.yml](config/deploy.yml) - Kamal deployment configuration
- [Dockerfile](Dockerfile) - Production Docker image definition

## Usage

### Creating a Tenant

Tenants must be created via Rails console or database migration:

```ruby
tenant = Tenant.create!(
  name: "ACME Corp",
  subdomain: "acme",
  document_quota: 10000,
  rate_limit_per_minute: 100
)

# Save the API key (only available after creation)
puts "API Key: #{tenant.api_key}"
```

### API Request Examples

**Create a document:**

```bash
curl -X POST http://localhost:3000/v1/documents \
  -H "X-API-Key: your-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "title": "Sample Document",
      "content": "This is the content of the document",
      "metadata": {"author": "John Doe"}
    }
  }'
```

**Search documents:**

```bash
curl http://localhost:3000/v1/search?q=sample&page=1&per_page=20 \
  -H "X-API-Key: your-api-key-here"
```

**Retrieve a document:**

```bash
curl http://localhost:3000/v1/documents/1 \
  -H "X-API-Key: your-api-key-here"
```

**Delete a document:**

```bash
curl -X DELETE http://localhost:3000/v1/documents/1 \
  -H "X-API-Key: your-api-key-here"
```

## Development

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/document_test.rb

# Run with RSpec (if configured)
bundle exec rspec
```

### Code Quality

```bash
# Run RuboCop linter
bundle exec rubocop

# Run Brakeman security scanner
bundle exec brakeman
```

## Performance Features

- **Caching**: Search results cached for 10 minutes, documents cached for 1 hour
- **Circuit Breaker**: Automatic fallback to SQL search when Weaviate is unavailable
- **Rate Limiting**: Configurable per-tenant rate limits with Redis-backed sliding window
- **Connection Pooling**: Redis connection pooling for efficient resource utilization
- **Weaviate BM25 Search**: Efficient keyword-based search with relevance scoring

## Monitoring

The application includes:

- Health check endpoints at `/health` and `/up`
- Search analytics tracking (query, results count, response time)
- Lograge for structured logging
- Circuit breaker metrics for Weaviate availability

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Support

For issues, questions, or contributions, please refer to the project repository.
