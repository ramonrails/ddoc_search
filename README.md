# DDoc Search

A high-performance, multi-tenant document search API built with Ruby on Rails. This application provides full-text search capabilities powered by Elasticsearch, with support for tenant isolation, rate limiting, caching, and asynchronous document indexing via Kafka.

## Overview

DDoc Search is designed to handle document storage and search for multiple tenants with the following key features:

- **Multi-tenant Architecture**: Complete data isolation per tenant with subdomain-based routing
- **Full-text Search**: Powered by Elasticsearch with custom analyzers and highlighting
- **Asynchronous Processing**: Kafka-based message queue for document indexing operations
- **High Performance**: Redis caching, circuit breakers, and rate limiting
- **Scalable Design**: Horizontal scaling support with configurable shards and replicas
- **RESTful API**: Clean JSON API with comprehensive error handling

## Architecture

### Technology Stack

- **Framework**: Ruby on Rails 8.0.3
- **Ruby Version**: 3.3.0 (3.4.7 for Docker)
- **Database**: SQLite3 (development/test), with support for multiple databases in production
- **Search Engine**: Elasticsearch 8.0
- **Cache**: Redis 5.0 with connection pooling
- **Message Queue**: Kafka (via Karafka 2.4)
- **Background Jobs**: Sidekiq 7.0
- **Web Server**: Puma with Thruster (production)
- **Containerization**: Docker with Kamal deployment

### Key Components

- **Tenant Middleware**: Request-level tenant identification via API keys
- **Circuit Breaker**: Prevents cascading failures to Elasticsearch
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
- Elasticsearch 8.0+
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

   # Elasticsearch
   ELASTICSEARCH_URL=http://localhost:9200

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

5. **Configure Elasticsearch**

   Ensure Elasticsearch is running, then create the index:

   ```bash
   rails console
   > Document.__elasticsearch__.create_index! force: true
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
  -e ELASTICSEARCH_URL=http://elasticsearch:9200 \
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

- [config/initializers/elasticsearch.rb](config/initializers/elasticsearch.rb) - Elasticsearch client configuration
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
- **Circuit Breaker**: Automatic fallback to SQL search when Elasticsearch is unavailable
- **Rate Limiting**: Configurable per-tenant rate limits with Redis-backed sliding window
- **Connection Pooling**: Redis connection pooling for efficient resource utilization
- **Elasticsearch Optimization**: 10 shards, 2 replicas, custom analyzers with snowball stemming

## Monitoring

The application includes:

- Health check endpoints at `/health` and `/up`
- Search analytics tracking (query, results count, response time)
- Lograge for structured logging
- Circuit breaker metrics for Elasticsearch availability

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Support

For issues, questions, or contributions, please refer to the project repository.
