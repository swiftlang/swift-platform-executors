# Apple Developer Content Guide - Swift Server focus - summary for LLMs

# 1. Core API Documentation Standards

## 1.1 Method and Function Documentation

### 1.1.1 Abstract Requirements
- **Structure**: One sentence starting with active verb phrase ending in 's'
- **Length**: 150 characters maximum, use full limit effectively
- **Voice**: Active voice only, avoid passive forms like "Invoked when" or "called when"
- **Content**: Explain task performed or information provided, not just method name repetition

### 1.1.2 Abstract Patterns by Function Type
- **Boolean returns**: "Returns a Boolean value that..." for primary behavior
- **Action methods**: Start with action verb if Boolean return is incidental
- **Information methods**: "Returns information about..." with specific details

### 1.1.3 Parameter Documentation Standards
- **Format**: Sentence fragment for first sentence, complete sentences for additional detail
- **Boolean parameters**: "If `true`..." or "If `false`..."
- **Integer parameters**: Include units and acceptable ranges
- **Result parameters**: State `Result` type, describe `success` and `failure` cases
- **Structure parameters**: "A structure that..." or "A pointer to a structure..."
- **Output parameters**: "On output, ..." for output-only values
- **Input/Output parameters**: "On input, ..." then "On output, ..."
- **Closure parameters**: Describe purpose, return value, end with parameter list

### 1.1.4 Parameter Documentation Requirements
- **Essential questions**: Purpose, acceptable value ranges, special value meanings
- **Memory management**: Specify caller responsibilities for allocation/release
- **Nil handling**: Explain behavior when `nil` passed as parameter
- **Complex interactions**: Document in Discussion section, not parameter table

### 1.1.5 Return Value Documentation
- **Format**: Noun phrase describing return value, start with most common result
- **Error handling**: List specific error values, indicate other errors possible
- **Boolean returns**: "Returns a Boolean value that..." or "Indicates whether..."
- **Integer returns**: Specify range and meaning
- **Result types**: Describe `success` and `failure` cases explicitly

### 1.1.6 Discussion Section Structure
- **Paragraph 1**: When and why to call the method
- **Subsequent paragraphs**: How to call the method, usage patterns
- **Side effects**: State changes, property modifications, system calls, expensive operations
- **Synchronization**: Specify synchronous vs asynchronous behavior
- **Threading**: Document thread safety requirements and restrictions
- **Override behavior**: Required vs optional, superclass call requirements

### 1.1.7 Code Examples
- **Requirement**: Provide realistic usage examples whenever possible
- **Context**: Show method in practical implementation scenarios
- **Best practices**: Demonstrate proper error handling and resource management

## 1.2 Class and Struct Documentation

### 1.2.1 Abstract Standards
- **Structure**: One-sentence noun phrase summarizing purpose
- **Length**: 150 characters maximum, use effectively
- **Content**: What class represents in big picture, avoid name repetition
- **Voice**: Active present-tense verbs, no passive voice

### 1.2.2 Overview Section Requirements
- **Paragraph 1**: What it is, what it does, why important
- **Paragraph 2**: Creation patterns - developer instantiation vs system provision
- **Paragraph 3+**: Fundamental usage concepts and patterns
- **Subsections**: Significant tasks that don't warrant separate articles

### 1.2.3 Essential Overview Questions
- **Purpose**: What does class do, when to use it
- **Instantiation**: Who creates instances, how, singleton vs multiple instances
- **Relationships**: Interaction with other objects, delegate patterns
- **Thread safety**: Threading requirements and restrictions
- **Lifecycle**: Creation, usage, and cleanup patterns

### 1.2.4 Class Design Patterns
- **Singleton pattern**: Document shared instance access and thread safety
- **Factory pattern**: Document creation methods and parameter requirements
- **Delegate pattern**: Link to delegate protocol, explain usage
- **Immutable/Mutable pairs**: Prefer immutable, document threading benefits

### 1.2.5 Task Group Organization
- **Titles**: Begin with gerund phrases (verb + ing)
- **Grouping**: Logical functionality clusters
- **Priority**: Most common operations first

## 1.3 Protocol Documentation

### 1.3.1 Abstract Requirements
- **Structure**: Noun phrase describing protocol instance and purpose
- **Content**: Non-obvious relevant details influencing adoption decisions
- **Voice**: Active present-tense, no passive voice
- **Length**: 150 characters maximum

### 1.3.2 Overview Section Content
- **Purpose**: Protocol tasks and developer use cases
- **Adoption**: How developers adopt in code, required base types
- **System integration**: When system returns protocol-adopting objects

### 1.3.3 Protocol Design Principles
- **Interface clarity**: Clear method and property requirements
- **Default implementations**: Document provided vs required implementations
- **Composition**: How protocols work together
- **Type constraints**: Generic constraints and associated types

### 1.3.4 Task Group Structure
- **Titles**: Gerund phrases (verb + ing)
- **Required methods**: Clearly distinguish from optional
- **Default implementations**: Document behavior and customization

## 1.4 Enumeration and Constants Documentation

### 1.4.1 Abstract Standards
- **Enumeration**: One-sentence noun phrase describing information represented
- **Constants**: Noun if constant *is* something, verb ending in 's' if *does* something
- **Length**: 150 characters maximum
- **Consistency**: Uniform part of speech within task groups

### 1.4.2 Content Requirements
- **Enumeration abstract**: What information type represents
- **Case abstracts**: Specific meaning and usage of each case
- **Value semantics**: What each constant represents or accomplishes
- **Usage context**: When and why to use specific values

### 1.4.3 Discussion Section
- **Purpose**: Elaborate on enumeration or constant representation
- **Usage patterns**: When and how to use different values
- **Relationships**: How constants relate to each other
- **Best practices**: Recommended usage patterns

### 1.4.4 Task Group Organization
- **Consistency**: All gerund phrases OR all noun phrases per page
- **Logical grouping**: Related constants together
- **Usage frequency**: Most common values first

## 1.5 Property Documentation

### 1.5.1 Abstract Standards
- **Structure**: One-sentence noun phrase describing stored value and meaning
- **Boolean properties**: "A Boolean value that..." format
- **Length**: 150 characters maximum
- **Content**: Property significance, not name repetition

### 1.5.2 Discussion Requirements
- **Typical usage**: How property affects class operation
- **Legal values**: Acceptable value ranges and constraints
- **Default value**: What default means and represents
- **Side effects**: Changes triggered by setting new values
- **Thread safety**: Threading restrictions and requirements

### 1.5.3 Boolean Property Documentation
- **True/false meaning**: Explicit clarification of both states
- **Default state**: Which Boolean value is default and why
- **Behavioral impact**: How true/false affects instance behavior

### 1.5.4 Closure Properties
- **Parameter documentation**: Term-definition list for closure parameters
- **Introduction**: "The closure takes the following parameters:"
- **Return behavior**: What closure returns and when
- **Execution context**: When and how closure is called

### 1.5.5 Property Design Patterns
- **Computed properties**: Document calculation and dependencies
- **Observed properties**: Document willSet/didSet behavior
- **Published properties**: Document subscriber notification patterns
- **Lazy properties**: Document initialization timing and thread safety

## 1.6 Source Code Comments

### 1.6.1 Comment Style Standards
- **Format**: Complete sentences or sentence fragments
- **Voice**: Active voice and second-person
- **Grammar**: Proper capitalization, spelling, grammar, punctuation
- **Line length**: 80-character column width maximum

### 1.6.2 Single-Line Comments
- **Format**: `// ` (two slashes + space) followed by comment text
- **Usage**: Explain code purpose and methodology
- **Placement**: Immediately before described code block

### 1.6.3 End-of-Line Comments
- **Format**: Single space after code, then comment
- **Alignment**: Do not align consecutive end-of-line comments
- **Length**: If exceeds 80 characters, move to line above code

### 1.6.4 Multi-Line Comments
- **Option 1**: Each line starts with `//`
- **Option 2**: Bracket with `/*` and `*/`
- **Line breaks**: Break at 80 characters
- **Nesting**: Avoid nested multiline comments for text

### 1.6.5 Switch Statement Comments
- **Placement**: Immediately before each case
- **Purpose**: Explain case-specific behavior
- **Clarity**: Make case logic and purpose explicit

### 1.6.6 Comment Content Guidelines
- **Methodology**: Explain approach and reasoning
- **Non-obvious logic**: Clarify complex or subtle code
- **Error handling**: Document error conditions and responses
- **Performance**: Note expensive operations or optimizations

## 1.7 Return Value Documentation

### 1.7.1 General Format
- **Structure**: Noun phrase describing what returns
- **Additional lines**: Complete sentences for complex returns
- **Figures/tables**: Place in Discussion section, not Return Value section

### 1.7.2 Method Type Patterns
- **Action methods**: Abstract starts with action verb, return details in Return Value section
- **Information methods**: Abstract starts with "Returns...", "Gets...", "Fetches...", "Retrieves..."
- **Return Value augmentation**: Add details beyond abstract information

### 1.7.3 Boolean Return Values
- **Abstract format**: "Returns a Boolean value indicating whether..." or "Indicates whether..."
- **Avoid**: "Returns whether..." (grammatically incorrect)
- **Simple opposites**: "true when [condition]; otherwise, false"
- **Complex false**: Explain additional false value meanings

### 1.7.4 Integer Return Values
- **Range specification**: Document acceptable value ranges
- **Meaning**: Explain what integer values represent
- **Special values**: Document special meanings (e.g., -1 for not found)
- **Units**: Specify measurement units when applicable

### 1.7.5 Result Type Returns
- **Type declaration**: State that return type is `Result`
- **Success case**: Describe successful return value
- **Failure case**: Describe error conditions and types
- **Usage patterns**: How to handle both cases

### 1.7.6 Nullable Returns
- **Objective-C initializers**: "A new [ObjectName] object or `nil` if unable to create"
- **Optional returns**: Explain when `nil` returned and why
- **Error conditions**: Document failure scenarios leading to `nil`

### 1.7.7 When to Omit Return Value Section
- **Swift initializers**: Don't return values, omit section
- **Void methods**: No return value, omit section
- **Abstract sufficiency**: When abstract fully describes return

## 1.8 Operator Documentation

### 1.8.1 Operator Terminology
- **Accurate descriptions**: Use precise operator names
- **Avoid**: "sign" or "symbol" terminology
- **No quotation marks**: Around operator descriptions
- **Consistency**: Use standard operator naming conventions

### 1.8.2 Comparison Operators
- `==`: equal-to operator
- `!=`: not-equal-to operator  
- `>`: greater-than operator
- `<`: less-than operator
- `>=`: greater-than-or-equal-to operator
- `<=`: less-than-or-equal-to operator

### 1.8.3 Identity Operators
- `===`: identical-to operator
- `!==`: not-identical-to operator

### 1.8.4 Custom Operator Documentation
- **Purpose**: Explain operator's specific function
- **Precedence**: Document operator precedence relationships
- **Associativity**: Left, right, or none associativity
- **Usage examples**: Show proper operator usage in context

### 1.8.5 Operator Overloading
- **Type-specific behavior**: How operator works with specific types
- **Performance characteristics**: Computational complexity when relevant
- **Error conditions**: When operator might fail or throw
- **Best practices**: Recommended usage patterns and conventions

# 2. Server-Side Architecture and APIs

## 2.1 API Collections and Organization

### 2.1.1 Hierarchical Content Structure
- **API collections organize large subsets of symbols, articles, and content** with hierarchical structure
- **Collections include more than APIs**: reference documentation, sample code, articles, tutorials, entitlements, configuration keys
- **Create collections when**:
  - 10+ items warrant collection creation
  - Content supports 2+ task groups
  - Content divisible from parent page
  - Content complex enough for additional discussion

### 2.1.2 Collection Design Principles
- **Shallow hierarchies preferred over deep nesting**
- **Titles must be noun phrases** representing collections of items
- **Titles specific and mutually exclusive** for clear navigation
- **Abstracts limited to 150 characters** using imperative phrases
- **Active voice, present-tense verbs** without passive construction

### 2.1.3 Task Group Organization
- **Noun phrases for object-oriented frameworks**
- **Gerund phrases for procedural frameworks** (Apple Music API, App Store Connect API, ApplicationServices, Core Audio, Dispatch)
- **Task groups require abstracts** explaining purpose and usage
### 2.1.4 Server-Side Collection Patterns
- **Network service collections**: Group HTTP clients, URL session management, authentication handlers
- **Data persistence collections**: Organize Core Data stacks, database connections, caching mechanisms
- **Concurrency collections**: Structure async/await patterns, actor implementations, task management
- **Configuration collections**: Bundle environment variables, feature flags, service discovery
- **Monitoring collections**: Aggregate logging, metrics, health checks, distributed tracing

### 2.1.5 Cross-Platform API Organization
- **Platform-agnostic interfaces**: Define protocol-based abstractions for server components
- **Implementation collections**: Separate platform-specific implementations (Linux, macOS, Docker)
- **Shared utilities**: Common algorithms, data structures, validation logic
- **Integration points**: External service connectors, message queue interfaces, database adapters

### 2.1.6 Collection Hierarchy Examples
```
Server Framework
├── Network Services
│   ├── HTTP Client Management
│   ├── WebSocket Connections
│   └── Service Discovery
├── Data Layer
│   ├── Repository Patterns
│   ├── Database Connections
│   └── Caching Strategies
└── Infrastructure
    ├── Configuration Management
    ├── Logging and Monitoring
    └── Security and Authentication
```


## 2.2 Framework and Technology Documentation

### 2.2.1 Framework Naming Conventions
- **Add spaces between words** (Apple Pay on the Web, Latent Semantic Mapping)
- **No spaces in feature names** (QuickLook, SwiftUI, ColorSync, DeviceCheck)
- **No spaces after letter prefixes** (AVFAudio, CFNetwork, IOKit, OSLog)
- **No spaces for Kit frameworks** (NetworkingDriverKit, SCSIPeripheralsDriverKit)
- **No spaces for Core frameworks** (ImageCaptureCore, JavaScriptCore)
- **Space before I/O suffix** (Core Media I/O, Image I/O, Model I/O)
- **Space before API, JS, UI suffixes** (Apple Music API, File Provider UI)

### 2.2.2 Framework Page Structure
- **Abstract starts with imperative verb** describing framework services
- **150-character limit** for search optimization
- **Overview introduces key features** and crucial terminology
- **Motivation explains when to use framework**
- **Keep overview under one screen** of content

### 2.2.3 Essentials Task Group
### 2.2.4 Server Framework Abstracts
- **Network frameworks**: "Build scalable HTTP services and WebSocket connections"
- **Data frameworks**: "Manage persistent storage and caching layers efficiently"
- **Security frameworks**: "Implement authentication, authorization, and encryption"
- **Monitoring frameworks**: "Track application performance and system health"

### 2.2.5 Server-Specific Overview Content
- **Architecture patterns**: Microservices, monoliths, serverless deployment models
- **Scalability considerations**: Load balancing, horizontal scaling, resource management
- **Integration capabilities**: Database connections, message queues, external APIs
- **Deployment targets**: Linux servers, container orchestration, cloud platforms
- **Performance characteristics**: Throughput, latency, memory usage, CPU utilization

### 2.2.6 Technology Integration Points
- **Swift Package Manager**: Dependency management and modular architecture
- **Docker containerization**: Deployment packaging and environment consistency
- **Database integrations**: PostgreSQL, MongoDB, Redis connection patterns
- **Message brokers**: RabbitMQ, Apache Kafka, AWS SQS integration
- **Observability tools**: Prometheus metrics, distributed tracing, structured logging

- **Include only when specific setup required** before framework use
- **Must be first task group** on framework page
- **Include for blocking requirements**:
  - User authorization (TCC dialogs)
  - Required class implementation
  - Mandatory setup processes
- **Minimize items** to avoid complexity perception
- **Framework page exclusive** - not for API collections

## 2.3 Framework Reference Documentation

### 2.3.1 Documentation Architecture
- **Technology pages as entry points** for frameworks and technologies
- **Hierarchical organization**: Overview → Topics → Reference/Articles/Samples
- **Cross-platform coverage**: iOS, iPadOS, macOS, tvOS, visionOS, watchOS
- **Non-framework technologies supported** (Apple silicon, REST APIs)

### 2.3.2 Reference Categories
- **Navigation pages**: Framework pages, API collections
- **Core types**: Classes, structures, protocols
### 2.3.4 Server-Side Reference Categories
- **Network layer documentation**: HTTP handlers, middleware, routing mechanisms
- **Data access patterns**: Repository interfaces, ORM abstractions, connection pooling
- **Concurrency primitives**: Actor systems, async sequences, structured concurrency
- **Configuration management**: Environment-based settings, feature toggles, service discovery
- **Security implementations**: JWT handling, OAuth flows, encryption utilities

### 2.3.5 Cross-Platform Documentation Strategy
- **Protocol-first design**: Abstract interfaces before concrete implementations
- **Platform-specific sections**: Linux-specific, macOS-specific, container-specific guidance
- **Integration examples**: Database connections, message queue usage, external service calls
- **Performance documentation**: Benchmarking, profiling, optimization techniques
- **Deployment guidance**: Container images, orchestration, scaling strategies

### 2.3.6 Server Framework Documentation Patterns
```
Server Technology Page
├── Overview (architecture patterns, use cases)
├── Essentials (required setup, dependencies)
├── Core Components
│   ├── HTTP Server Implementation
│   ├── Request/Response Handling
│   └── Middleware Architecture
├── Data Layer
│   ├── Database Integration
│   ├── Caching Strategies
│   └── Data Validation
├── Infrastructure
│   ├── Configuration Management
│   ├── Logging and Monitoring
│   └── Security Implementation
└── Deployment
    ├── Container Configuration
    ├── Scaling Strategies
    └── Production Considerations
```

- **Methods and properties**: Functions, properties, constants, notifications
- **Swift-specific**: Modifiers, cross-import overlays
- **External APIs**: REST endpoints, JSON objects
- **Configuration**: Property lists, entitlements
- **Lifecycle management**: Deprecated symbols

### 2.3.3 Documentation Tools Integration
- **Xcode and DocC integration** for symbol documentation
- **Snapshot tools** for documentation validation
- **Automated reference generation** from source code

## 2.4 REST API Documentation

### 2.4.1 Endpoint Documentation Structure
- **Title-style capitalization** for endpoint names
- **Imperative verb abstracts** describing endpoint function
- **150-character abstract limit** with complete sentences
- **Parameter descriptions start with noun phrases**
- **Term-definition lists** for value enumeration

### 2.4.2 HTTP Documentation Sections
- **Parameters section**:
  - Noun phrase descriptions with additional sentences
### 2.4.4 Server API Endpoint Patterns
- **Resource-based URLs**: `/api/v1/users/{id}`, `/api/v1/orders/{orderId}/items`
- **Action-based endpoints**: `/api/v1/auth/login`, `/api/v1/cache/invalidate`
- **Bulk operations**: `/api/v1/users/batch`, `/api/v1/notifications/broadcast`
- **Health and monitoring**: `/health`, `/metrics`, `/ready`, `/live`

### 2.4.5 Server-Side Parameter Documentation
- **Path parameters**: Resource identifiers, version numbers, tenant IDs
- **Query parameters**: Filtering, pagination, sorting, field selection
- **Header parameters**: Authentication tokens, content negotiation, tracing headers
- **Body parameters**: Resource creation, updates, bulk operations

### 2.4.6 HTTP Method Documentation Standards
- **GET endpoints**: Resource retrieval, collection listing, health checks
- **POST endpoints**: Resource creation, action execution, data processing
- **PUT endpoints**: Resource replacement, bulk updates, configuration changes
- **PATCH endpoints**: Partial updates, field modifications, status changes
- **DELETE endpoints**: Resource removal, cleanup operations, cache invalidation

### 2.4.7 Server Response Patterns
- **Success responses**: 200 (OK), 201 (Created), 202 (Accepted), 204 (No Content)
- **Client error responses**: 400 (Bad Request), 401 (Unauthorized), 403 (Forbidden), 404 (Not Found)
- **Server error responses**: 500 (Internal Server Error), 502 (Bad Gateway), 503 (Service Unavailable)
- **Custom error formats**: Structured error objects with codes, messages, details

### 2.4.8 Authentication and Authorization Documentation
- **Bearer token authentication**: JWT tokens, API keys, OAuth 2.0 flows
- **Request signing**: HMAC signatures, request timestamps, nonce values
- **Role-based access**: Permission matrices, resource ownership, tenant isolation
- **Rate limiting**: Request quotas, throttling policies, backoff strategies

  - System-generated required/optional indicators
  - Optional summary for preconditions
- **HTTP header section**:
  - Optional summary for global preconditions
  - Individual header field descriptions
- **HTTP body section**:
  - Optional summary for body requirements
  - Field-specific documentation

### 2.5.4 Server-Side JSON Schema Patterns
- **Request schemas**: Input validation, required fields, data types, constraints
- **Response schemas**: Output structure, optional fields, nested objects, arrays
- **Error schemas**: Standardized error formats, error codes, detail messages
- **Configuration schemas**: Environment settings, feature flags, service parameters

### 2.5.5 Data Transfer Object Documentation
- **Entity representations**: User objects, order objects, product catalogs
- **Command objects**: Action requests, batch operations, configuration updates
- **Event objects**: Notification payloads, audit logs, state changes
- **Metadata objects**: Pagination info, timestamps, version numbers

### 2.5.6 JSON Validation and Constraints
- **Type validation**: String formats, numeric ranges, boolean flags
- **Pattern validation**: Email formats, UUID patterns, custom regex
- **Structural validation**: Required properties, object nesting, array constraints
- **Business rule validation**: Cross-field dependencies, conditional requirements

### 2.5.7 Server JSON Processing Examples
```json
{
  "user": {
    "id": "uuid-string",
    "email": "email-format",
    "profile": {
      "name": "string",
      "preferences": {
        "notifications": "boolean",
        "theme": "enum-value"
      }
    },
    "metadata": {
      "createdAt": "iso-datetime",
      "lastLogin": "iso-datetime",
      "version": "integer"
    }
  }
}
```

### 2.4.3 Response and Examples
- **Response codes section** for status documentation
- **Discussion section covers**:
  - Endpoint preconditions
  - Behavior details
  - Parameter interactions
  - Side effects
- **Request/response examples**:
  - Successful request/response pairs
  - Unsuccessful examples with explanations

## 2.5 JSON Object Documentation

### 2.5.1 Object Documentation Standards
- **Abstract starts with noun phrase** describing object representation
- **150-character limit** with complete sentences
- **Resource object pattern** for API entities

### 2.5.2 Property Documentation
- **Noun phrase descriptions** with additional sentences
### 2.6.4 Server Configuration Constants
- **Environment constants**: Development, staging, production configurations
- **Service constants**: Database connection strings, API endpoints, timeout values
- **Feature flags**: Boolean toggles for functionality, A/B testing parameters
- **Security constants**: Encryption keys, token expiration times, rate limits

### 2.6.5 Network and Protocol Constants
- **HTTP status codes**: Custom application codes, error categorization
- **Content types**: MIME types, encoding specifications, format identifiers
- **Protocol versions**: API versions, schema versions, compatibility markers
- **Timeout constants**: Connection timeouts, request timeouts, retry intervals

### 2.6.6 Server Enumeration Patterns
```swift
enum ServerEnvironment: String, CaseIterable {
    case development = "dev"
    case staging = "stage"
    case production = "prod"
}

enum DatabaseType: String {
    case postgresql = "postgres"
    case mongodb = "mongo"
    case redis = "redis"
}

enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
}
```

- **Term-definition lists** for value meanings
- **System-generated required/optional indicators**
- **Boolean properties**: "A Boolean value that..." format
- **Avoid value enumeration** when meaning is clear

### 2.5.3 JSON Object Examples
- **Albums**: Resource object representing album entities
- **Storefronts**: Territory availability representation
- **Transaction items**: Line item charge representations

## 2.6 Enumeration and Constants Curation

### 2.6.1 Supporting Type Placement
- **Place next to primary symbol** that uses the type
- **Single task group placement** - avoid multiple groups on same page
- **Most prominent group selection** for placement
- **Avoid dedicated "Supporting Types" groups**

### 2.6.2 Multi-Page Type Distribution
- **Include on each page needing the type** (up to 3 pages)
- **Hoist to higher hierarchy level** when used on 3+ pages
- **Indicates importance** requiring higher placement

### 2.6.3 Multiple Type Organization
- **Curate after supporting method/property**
### 2.7.4 Server-Side Delegate Patterns
- **Request delegates**: HTTP request processing, middleware execution, error handling
- **Connection delegates**: Database connection management, pool lifecycle, failover handling
- **Service delegates**: External service integration, circuit breaker patterns, retry logic
- **Event delegates**: Message processing, event sourcing, notification distribution

### 2.7.5 Data Source Implementation Patterns
- **Repository data sources**: Database query execution, result mapping, transaction management
- **Cache data sources**: Memory caching, distributed caching, cache invalidation strategies
- **Stream data sources**: Real-time data feeds, message queue consumption, event streaming
- **Configuration data sources**: Environment variable loading, feature flag resolution, secret management

### 2.7.6 Server Delegate Organization Examples
```swift
// HTTP Server Delegate Pattern
class HTTPServer {
    weak var requestDelegate: HTTPRequestDelegate?
    weak var errorDelegate: HTTPErrorDelegate?
}

protocol HTTPRequestDelegate: AnyObject {
    func server(_ server: HTTPServer, didReceive request: HTTPRequest) async -> HTTPResponse
    func server(_ server: HTTPServer, willProcess request: HTTPRequest)
    func server(_ server: HTTPServer, didProcess request: HTTPRequest, response: HTTPResponse)
}

// Database Connection Delegate Pattern
class DatabasePool {
    weak var connectionDelegate: DatabaseConnectionDelegate?
}

protocol DatabaseConnectionDelegate: AnyObject {
    func pool(_ pool: DatabasePool, didEstablish connection: DatabaseConnection)
    func pool(_ pool: DatabasePool, didLose connection: DatabaseConnection, error: Error)
    func pool(_ pool: DatabasePool, shouldRetry connection: DatabaseConnection) -> Bool
}
```

- **Sequential organization** within task groups
- **Split large groups** when enumerations make groups too big
- **Maintain logical grouping** of related constants

## 2.7 Delegates and Data Sources

### 2.7.1 Delegate Placement Strategy
- **Nest inside supporting class** in same task group as delegate property
- **Place directly underneath** delegate/dataSource property
- **Data source before delegate** when both present (data sources usually required)

### 2.7.2 Task Group Organization
- **Required delegates/data sources**: Top of page after initialization
- **Optional delegates**: Appropriate location based on usage patterns
- **Multiple delegates**: Separate task groups for different purposes
- **Task group titles describe purpose** not just "delegate"

### 2.7.3 Delegate Promotion
- **Promote fundamental delegates** to framework level
- **Same task group as supported class**
- **Addition to class nesting** - not replacement
- **Framework-critical patterns** warrant promotion
### 2.8.4 Server Protocol Conformance Examples
- **Codable conformance**: JSON serialization, request/response mapping, data persistence
- **Hashable conformance**: Dictionary keys, set membership, caching strategies
- **Comparable conformance**: Sorting algorithms, priority queues, version comparisons
- **CustomStringConvertible**: Logging output, debugging information, error messages

### 2.8.5 Server-Side Protocol Extensions
```swift
// HTTP Response Protocol Extensions
extension HTTPResponse: CustomStringConvertible {
    var description: String {
        "HTTPResponse(status: \(statusCode), headers: \(headers.count))"
    }
}

// Database Entity Protocol Extensions
extension DatabaseEntity: Codable where Self: Identifiable {
    // Automatic JSON encoding/decoding for API responses
}

// Service Configuration Protocol Extensions
extension ServiceConfiguration: Equatable, Hashable {
    // Enable configuration comparison and caching
}
```

### 2.8.6 Async Protocol Implementations
- **AsyncSequence conformance**: Stream processing, event handling, data pipelines
- **AsyncIteratorProtocol**: Custom iteration patterns, lazy evaluation, resource management
- **Actor protocol conformance**: Thread-safe state management, concurrent access patterns
- **Sendable conformance**: Cross-actor communication, concurrent data structures


## 2.8 Default Implementations

### 2.8.1 Protocol Conformance Handling
- **Swift protocol conformance** creates inherited methods
- **DocC automatic curation** into "Default implementations" groups
- **API collection per protocol** for organization
- **Prevents method proliferation** on conforming types

### 2.8.2 Multiple Protocol Conformance
- **Separate API collections** for each protocol
- **Individual protocol organization** (OptionSet, Equatable, SetAlgebra)
- **Clear protocol attribution** for inherited methods

### 2.8.3 Implementation Examples
- **SwiftUI View conformance**: Grid inheriting View methods
- **Multiple conformance**: Axis.Set with three protocol collections
- **Automatic inheritance management** through DocC tooling

## 2.9 Base Abstract Classes

### 2.9.1 Abstract Class Placement
- **List after subclasses** in same task group
### 2.9.4 Server Base Class Patterns
- **Service base classes**: Common service lifecycle, dependency injection, configuration management
- **Handler base classes**: Request processing patterns, error handling, response formatting
- **Repository base classes**: Data access patterns, connection management, query optimization
- **Middleware base classes**: Request/response transformation, authentication, logging

### 2.9.5 Abstract Server Component Examples
```swift
// Abstract HTTP Handler Base Class
abstract class HTTPHandler {
    let configuration: HandlerConfiguration
    let logger: Logger
    
    init(configuration: HandlerConfiguration, logger: Logger) {
        self.configuration = configuration
        self.logger = logger
    }
    
    // Abstract methods for subclasses
    func handle(_ request: HTTPRequest) async throws -> HTTPResponse
    func validateRequest(_ request: HTTPRequest) throws
    func formatResponse(_ data: Any) throws -> HTTPResponse
}

// Concrete Handler Implementations
class UserHandler: HTTPHandler {
    override func handle(_ request: HTTPRequest) async throws -> HTTPResponse {
        try validateRequest(request)
        let userData = try await processUserRequest(request)
        return try formatResponse(userData)
    }
}

// Abstract Database Repository
abstract class Repository<Entity: Codable & Identifiable> {
    let connection: DatabaseConnection
    let tableName: String
    
    // Common CRUD operations
    func find(id: Entity.ID) async throws -> Entity?
    func findAll() async throws -> [Entity]
    func save(_ entity: Entity) async throws -> Entity
    func delete(id: Entity.ID) async throws
    
    // Abstract methods for customization
    func buildQuery(for operation: DatabaseOperation) -> String
    func mapResult(_ result: DatabaseResult) throws -> Entity
}
```

### 2.9.6 Server Architecture Inheritance Patterns
- **Layered architecture**: Controller → Service → Repository inheritance chains
- **Plugin architecture**: Base plugin classes with specialized implementations
- **Middleware chains**: Base middleware with specific processing implementations
- **Event handling**: Base event processors with domain-specific handlers

- **Separate task group** when many subclasses or different groups
- **Bottom page placement** for separate groups

### 2.9.2 Organization Patterns
- **Simple inheritance**: Base class after subclasses in same group
- **Complex inheritance**: Dedicated task group for base classes
- **Wide functionality coverage**: Separate organization required

### 2.9.3 Abstract Class Examples
- **PKObject pattern**: Base for PKPass and PKPaymentPass
- **HKObject pattern**: Multiple subclasses across functionality areas
- **Framework-wide base classes**: Separate task group organization

## 2.10 Deprecated Symbol Handling

### 2.10.1 Deprecation Types
- **Formal deprecation**: Compiler warnings with deprecation macros
- **Soft deprecation**: Discouraged use without formal tagging
- **Symbol removal**: Post-deprecation elimination from SDK

### 2.10.2 Deprecation Documentation
- **Deprecation summaries** for formally deprecated symbols
- **"Use replacement instead"** format with links
- **Discussion text** for soft deprecations
### 2.10.5 Server-Side Deprecation Strategies
- **API versioning**: Maintain deprecated endpoints with version prefixes (`/api/v1/deprecated`, `/api/v2/current`)
- **Feature flags**: Gradual deprecation through configuration toggles and runtime switches
- **Migration guides**: Step-by-step replacement instructions with code examples
- **Backward compatibility**: Adapter patterns maintaining old interfaces while using new implementations

### 2.10.6 Server Deprecation Documentation Examples
```swift
// Deprecated HTTP Handler
@available(*, deprecated, message: "Use AsyncHTTPHandler instead")
class SyncHTTPHandler {
    /// Apple discourages the use of this synchronous handler.
    /// Use AsyncHTTPHandler for better performance and resource management.
    func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        // Legacy synchronous implementation
    }
}

// Replacement Implementation
class AsyncHTTPHandler {
    /// Modern asynchronous HTTP request handler with improved performance.
    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        // New async implementation
    }
}

// Deprecated Configuration Pattern
@available(*, deprecated, message: "Use EnvironmentConfiguration instead")
struct LegacyConfiguration {
    /// Apple discourages the use of this configuration pattern in server environments.
    /// Use EnvironmentConfiguration for better security and deployment flexibility.
}
```

### 2.10.7 Migration Path Documentation
- **Deprecation timeline**: Clear schedules for removal with major version boundaries
- **Breaking change notifications**: Advance warning for API consumers and integrators
- **Compatibility matrices**: Version support tables showing deprecated/supported combinations
- **Automated migration tools**: Scripts and utilities for code transformation

### 2.10.8 Server Legacy Symbol Management
- **Legacy API collections**: "Legacy Network APIs", "Legacy Database Connections"
- **Sunset schedules**: Planned removal dates with sufficient advance notice
- **Support boundaries**: Clear end-of-life dates for deprecated server components
- **Security considerations**: Vulnerability management for deprecated but still-used components

### 2.10.9 Deprecation Communication Patterns
- **Compiler warnings**: Formal deprecation attributes with replacement guidance
- **Runtime warnings**: Logging deprecated usage in development environments
- **Documentation badges**: Visual indicators in reference documentation
- **Migration assistance**: Support channels and resources for developers transitioning away from deprecated APIs
- **Guidance provision** when no replacement exists

### 2.10.3 Curation Adjustments
- **Move to bottom** of groups/pages/frameworks
- **1-2 symbols**: Bottom of immediate task group
- **Entire task group**: Bottom of page
- **3+ classes or 5+ symbols**: Dedicated API collection

### 2.10.4 Deprecated Collections
- **"Deprecated" task group** with "Deprecated Symbols" API collection
- **"Review unsupported symbols and their replacements"** abstract
- **Type-based task groups**: Deprecated Methods, Deprecated Properties
- **Legacy symbols**: "Legacy" task groups with avoidance abstracts

# 3. Documentation Principles and Writing Standards

## 3.1 Developer Content Principles

### Core Documentation Principles
- **Accuracy**: Single most important theme - provide accurate, up-to-date, functional information
- **Inclusivity**: Make content accessible to diverse audiences with varying experience levels
- **Clarity**: Communicate directly using fewest, simplest words
- **Consistency**: Follow established standards for reliable, recognizable voice

### Accuracy Standards
- Verify all information through subject matter experts and peer review
- Demonstrate best practices with working examples
- Avoid speculative commentary or unverified predictions
- Stick to verifiable facts and current functionality
- Include review processes in writing workflow
- Test all code examples and procedures

### Inclusivity Guidelines
- Define technical terms upon introduction
- Use effective examples and specific rather than general statements
- Craft simple, readable sentences avoiding insider jargon
- Provide clear transitions between concepts and logical organization
- Include references for further exploration
- Plan for review and revision from diverse perspectives

### Clarity Requirements
- Use most direct communication path possible
- Provide factual, actionable information
- Organize information by priority: basic to advanced, simple to complex, most to least important
- Address ambiguity through clear connections between concepts
- Avoid excessive repetition that diminishes impact
- Curate information to find simplest route to task completion

### Consistency Implementation
- Follow established style guidelines and standards
- Build on collective knowledge and insight
- Maintain recognizable, trustworthy voice across documentation
- Ensure content feels familiar and reliable to audience

## 3.2 Authoring Developer Content

### Content Creation Goals
- Share knowledge and expertise to empower developers
- Enable practical, compelling, and satisfying development experience
- Inform, educate, and transmit actionable knowledge
- Foster discussion, originality, and community engagement

### Content Format Options
- Code examples: snippets, comments, samples
- Documentation: reference pages, articles, technical guides
- Visual aids: diagrams, flow charts, illustrations
- Combined formats: tutorials, code walkthroughs

### Developer Content Principles Application
- **Accuracy**: Create actionable documentation maintaining impeccable standards as source of truth
- **Inclusivity**: Write for diverse audience, seek perspectives beyond your own, create clear paths
- **Clarity**: Use direct communication, provide factual information, organize to resolve ambiguity
- **Consistency**: Follow style guidelines, build on collective knowledge, present consistent voice

### Content Strategy
- Choose format that works best for specific content
- Use multiple teaching strategies when appropriate
- Enable audience to accomplish tasks and reach goals
- Inspire developers to create something new with tools provided
- Deliver extraordinary product meeting high quality expectations

## 3.3 Technical Writing Basics

### Writing Process Framework
1. **Plan**: Define audience and purpose, gather context and research
2. **Write**: Compose and draft content
3. **Review**: Revise, refine, and collaborate with reviewers
4. **Publish**: Finalize and distribute content

### Planning Phase
- Define content's purpose and audience before writing
- Scope, organize, and focus content into useful, effective piece
- Balance detail level for different experience levels
- Consider existing documentation and reader's path through content
- Assess audience background and needs throughout process

### Audience Definition
- Write for audience new to technology while respecting experienced users
- Balance concrete steps with necessary context
- Stick close to learning objectives for decision-making
- Build community of learners and developers
- Treat experienced audience as standard bearers, new audience as future

### Research and Context
- Explore existing content in documentation library
- Map reader's path through documentation to reach goals
- Identify where readers start and steps they take
- Assess background knowledge requirements
- Look for gaps or repeated user questions

### Writing Phase
- Focus on composition and drafting without critical editing
- Allow ideas to accumulate in preliminary order
- Get thoughts and knowledge outside your head into shareable form
- Consider all possible concepts and strategies
- Save revision questions for later stages

### Review Process Types
1. **Technical Reviews**: Subject matter experts verify accuracy and functionality
2. **Peer Reviews**: Colleagues and fellow writers provide feedback
3. **Editorial Reviews**: Editors evaluate document effectiveness

### Collaboration Guidelines
- Writers and reviewers share same goal: successful, useful content
- Make review process conversational dialogue
- Investigate and ask questions about content and topics
- Suggest changes, propose solutions, provide options
- Listen carefully to responses and iterate as needed

### Review Focus Areas
- **Purpose and Audience**: What's being taught, who's the content for, what's the goal
- **Problem Orientation**: Is content task-based, does it answer "How do I"
- **Solutions**: Does it offer actionable solutions
- **Structure**: Title effectiveness, abstract quality, overview completeness
- **Sentence Level**: Grammar, punctuation, style, formatting

## 3.4 Purpose and Audience

### Content Purpose Definition
- Determine what you want to convey and teach
- Identify if fixing/improving something or explaining something new
- Define learning objectives and audience takeaways
- Choose best format: task-based article, sample code, tutorial
- Establish clear thesis and purpose for decision-making

### Purpose-Defining Questions
1. What do I want to convey and teach?
2. Am I fixing/improving or explaining something new?
3. What will audience gain and know how to do?
4. What are the learning objectives?
5. What's the best way to learn this material?

### Learning Objectives Focus
1. Determine requirements and specifications of topic
2. Identify problems reader needs to solve
3. Define what they're trying to build or accomplish
4. Break down required information into clear chronology
5. Assess background context needed for understanding

### Audience Definition Process
- Understand audience needs to make effective content decisions
- Determine format and scope based on audience experience level
- Balance detail for beginners vs. advanced users
- Consider overlap between beginning and advanced audiences
- Account for experienced developers new to specific features

### Audience Definition Exercise
1. **Job and Role**: Identify specific titles, roles, responsibilities
2. **Skills and Experience**: List knowledge, years of experience, technology familiarity
3. **Daily Activities**: What they do typically, what's expected of them
4. **Goals and Needs**: What they're trying to accomplish, information needed
5. **Distinguishing Aspects**: Additional characteristics that set them apart

### Content Context Analysis
1. Where does audience go for help or instruction?
2. What path would they follow through documentation?
3. What's missing from existing coverage?
4. Are there gaps or repeated user questions?

### Audience Definition Refinement
- Remember audience is never the author
- Step beyond your own opinions and understanding
- Ask "What does my reader need to know and do?"
- Creators and experts aren't the audience
- Represent and serve audience, not just topic itself

## 3.5 Abstract Standards

### Abstract Purpose and Placement
- Describe entity and what developer can use it to do
- Help developers decide relevance and whether to explore further
- Appear in search results requiring concise, standalone context
- Include keywords and buzzwords developers might search for
- Complement title with additional details, don't just repeat

### General Abstract Guidelines
- **Length**: 150 characters or fewer, single sentence or fragment
- **Content**: Don't repeat technical terms from entity name
- **Grammar**: Use correct style for specific entity type
- **Links**: Avoid links in abstracts
- **Formatting**: Avoid parentheses, slashes, platform-specific wording
- **Language**: Use plain English rather than literal symbol names

### Abstract Grammar by Entity Type

#### Noun Phrases
- Associated types, cases, classes, enumerations
- Properties, property list keys, protocols, structures
- Type aliases, variables

#### Imperative Verbs
- API collections, articles, frameworks
- Sample code project articles, task groups, technology pages

#### Verbs Ending in 's'
- Cases, functions, function macros, initializers
- Macros, methods, delegate methods, operators, subscripts

### Framework and Technology Abstracts
- Use imperative verb phrase describing services provided
- Framework consists of APIs; technology is broader category
- Abstract appears on top-level landing page and main documentation page
- Must be informative and succinct for search results

### API Collection Abstracts
- Begin with imperative verb describing what developer can do
- Avoid nonspecific actions like "learn" or "understand"
- Focus on concrete tasks and actions
- Describe what can be accomplished with entities in group

### Article Abstracts
- Use imperative verb summarizing developer actions
- Include keywords developers might search for
- Use problem-solution format
- Problem describes what developer searches for
- Solution explains how to solve the problem

### Task Group Abstracts
- Optional, can contain one or two sentences up to 150 characters
- Can include link if relevant to all items in group
- Use imperative or declarative statement
- Don't appear in search results, can benefit from longer descriptions

### Function and Method Abstracts
- Use verb ending with 's' describing what developer uses it to do
- Explain action performed or information provided
- Focus on developer perspective and usage

### Property Abstracts
- Use noun phrase indicating what information property stores
- Explain relevance or helpfulness for developers
- For Boolean properties, begin with "A Boolean value that"

### Enumeration and Constants
- Enumeration: one-sentence noun phrase
- Constants: noun if constant "is" something, verb ending in 's' if constant "does" something
- Maintain consistency within task group or page

## 3.6 Titles and Section Headings

### General Title Guidelines
- Limit titles and section headings to 60 characters or fewer
- Don't include literal symbol names except for reference/technology pages
- Use plain English equivalent instead of code symbols
- Don't include code font, italics, or links in titles
- Optimize for search engine optimization (SEO)

### Title Capitalization
- Use sentence-style capitalization for most content
- Capitalize first word and proper names/nouns only
- Treat Apple frameworks and tools as proper nouns
- Exception: Use title-style capitalization for REST API endpoints

### Title Grammar by Content Type

#### Gerunds (verb + ing)
- Article titles
- Task group titles for class, structure, protocol pages
- Task group titles for nonobject-oriented API collections

#### Nouns
- API collection titles
- Task group titles (except class, structure, protocol pages)

#### Imperative Verbs
- Section headings for articles
- Section headings for class, structure, enumeration pages

### API Collection Titles
- Use noun phrase representing entire collection
- Keep specific enough to include everything on page, no more
- Convey items that reside on underlying pages
- Focus on what's available rather than how to use it

### Article Titles
- Use gerund as first word describing task to perform
- Limit to 60 characters for best search results
- Be specific about what's being accomplished
- Complement with abstract using problem-solution format

### Sample Code Article Titles
- Start with gerund describing what sample code project does
- Don't include sample app name unless specifically approved
- Focus on descriptive action rather than implementation details
- Keep simple and direct

### Section Headings
- Begin with imperative verb for articles and reference pages
- Describe action developer can perform
- Address significant or nonobvious tasks
- Provide clear guidance for task completion

## 3.7 Task Group Organization

### Task Group Purpose
- Define set of tasks developers can perform with grouped items
- Guide developers through curation with descriptive titles
- Provide short, to-the-point organization
- Choose unique, mutually exclusive titles with clear meaning

### Task Group Title Guidelines
- **Length**: 2-5 words, maximum 40 characters
- **Capitalization**: Sentence case
- **Content**: No symbol names, italics, code font, or links
- **Specificity**: Encapsulate everything in group, nothing more

### Title Grammar by Page Type
- **Classes, Structures, Protocols**: Gerund phrases (action-oriented)
- **Enumerations**: Gerund phrases or noun phrases (be consistent)
- **All Other Pages**: Noun phrases
- **API Collections**: Noun phrases (exception for non-object-oriented frameworks)

### Essentials Task Group
- Include only for critical information required to use framework
- Put first task group on page when needed
- Include only tasks that might block developer success
- Minimize items to avoid intimidation
- Use only on framework page, not API collection pages

### Framework Page Task Groups
- Use noun phrases for all task group titles
- Give task groups object-like quality for quick identification
- Help developers discover what they can do with framework
- Point developers in right direction for their needs

### Class/Structure/Protocol Task Groups
- Use gerund phrases for action-oriented titles
- Put specific groups first
- Common patterns:
  - "Creating an [object-name]" group first
  - Delegate protocol group near top after creation groups
- Title delegate groups to evoke task developer performs

### Enumeration Task Groups
- Can use gerund phrases or noun phrases
- Be consistent within the page
- Consider that enumerations can have methods and operators, not just cases

### Task Group Abstracts
- Ideally not needed if title is clear
- Use when task group title needs additional explanation
- Start with imperative verb, maximum two sentences
- Explain why symbols are grouped together
- Consider breaking complex groups into smaller ones

## 3.8 Article Writing Guidelines

### Article Purpose and Structure
- Explain how to complete tasks and solve problems
- Answer "How do I?" questions with active voice and conversational tone
- Focus on actions rather than concepts and how-it-works information
- Target approximately 10 minutes reading time
- Require title, abstract, and Overview at minimum

### Article Components
- **Title**: Encapsulates overarching goal using gerund, 60 characters max
- **Abstract**: Summarizes actions to accomplish goal, 150 characters, imperative sentence
- **Overview**: Describes problem and summarizes developer action, 1-2 paragraphs
- **Sections**: Encapsulate actions that are part of main task

### Section Guidelines
- Write section headings in imperative voice
- Communicate action and goal in plain, meaningful English
- Teach developer how to perform action described in heading
- Give logical sequence without numbering headings
- Organize general to specific for nonsequential tasks

### Section Content Requirements
- Integrate concepts into articles wherever possible
- Include figure or code snippet to inform action
- Break main task into numbered steps when appropriate
- Keep steps to maximum three lines of text
- Avoid more than 2-3 consecutive paragraphs of text

### Code Listings and Figures
- Demonstrate points made in text
- Place after text that refers to them for context
- Prioritize code listings over figures when appropriate
- Ensure code comes from snippet projects
- Don't place within steps or lists

### Caption Guidelines
- Not required unless needed for clarity
- Write one-line gerund or noun phrase
- No period at end
- Capitalize only first letter and proper nouns
- Don't use code voice or styling

### Asides Usage
- **Note**: Relevant or tangential information
- **Tip**: Shortcuts or hints for task completion
- **Important**: Less serious but potential trouble spots
- **Warning**: Only for situations causing injury, damage, or data loss
- Place in appropriate context where information is needed
- Keep short and focused, use sparingly

### Article Organization Principles
- Don't create separate concept-only articles
- Integrate concepts into task-based articles
- Use parent-child relationships for complex information
- Parent describes high-level process, children provide details
- Limit child articles to seven or fewer per task group

### Curation Guidelines
- Place articles on framework or API collection pages
- Include alongside symbols that are primary focus
- May include in own task group for general processes
- Rarely curate on class/protocol pages unless content is solely focused there

## 3.9 Narrative Structure

### Story Crafting Principles
- Write with single, focused goal in mind
- Make articles engaging for all developers including those without technology-specific knowledge
- Keep structure simple and relatively flat
- Focus on clear and specific goals rather than vague objectives

### Content Focus Guidelines
- Define title, abstract, and goal before writing body
- Provide only enough information for task completion
- Include context for process and important decisions
- Link to details rather than including everything
- Use parent-child structure for complex task sets

### Problem-Solution Approach
- Don't discuss solutions until problem is clearly identified
- Help developers decide if they need to read further
- Explain problem first to establish relevance
- State problem clearly and communicate solution path

### Article Structure Best Practices
- Don't create multiple articles for same basic task
- Never split tasks into beginner and advanced versions
- Create single article starting with beginner story, explaining when advanced options apply
- Avoid concept-only articles as sole purpose
- Create separate articles for reusable tasks

### Content Development Strategy
- Check for existing articles about tasks before creating new ones
- Include best practice guidance in all articles
- Don't write about problems without offering solutions
- Avoid subsections within subsections (no third-level headings)
- Evaluate content complexity and refactor if needed

### Prototyping Process
- Define initial article set and be prepared for adjustments
- Throw out content that doesn't adhere to article's goal
- Create prototype drafts quickly as proof of concept
- Don't try for polished final draft initially
- Test narrative with mentors and others early

### Iteration Guidelines
- Don't be afraid to try dramatically different approaches
- Allow time to experiment with other options
- Seek advice from people who don't know the technology
- Show early drafts to team and mentors
- Use feedback to refine prototypes

### Content Polishing
- Maintain linear narrative without straying from learning path
- Avoid excessive asides or optional sections
- Put advanced optional tasks into child articles
- Clarify abstract concepts with tangible examples
- Resist urge to include every detail about technology

## 3.10 Curation Process

### Curation Definition and Goals
- Manual process of arranging symbols into groups promoting learning
- Direct readers to needed resources through logical organization
- Balance "promote learning" and "direct to resources" objectives
- Favor directing to resources when balancing both options

### Key Curation Principles
- Figure out what matters most to reader
- Create unique, mutually exclusive task group titles with clear meaning
- Choose titles that encapsulate group contents and nothing else
- Prototype curation using preferred tools
- Experiment with ideas that seem unorthodox

### Framework Curation Guidelines
- Organize objects into mutually exclusive task groups
- Present in order developer most likely needs them
- Use noun phrases for task group titles
- Create groups with minimal content overlap
- Make titles specific enough to encapsulate everything in group
- Use API Collections for large content subsets

### Procedural Framework Handling
- Apply to frameworks that aren't object-oriented
- Examples: ApplicationServices, Core Audio, Dispatch, REST APIs
- Organize around "faux objects" when possible
- Use API Collections to create faux objects
- Treat API Collection like class with gerund phrases for task group titles

### Class Curation Approach
- Show tasks that reader can perform with class
- Use gerund phrases for action-oriented task group titles
- Put specific groups first
- Common patterns: "Creating an [object-name]" group first
- Place delegate protocol task group near top after creation groups

### Curation Process Steps

#### Initial Curation
1. Define initial task groups broadly around major themes
2. Curate only major items initially (classes, protocols, methods, properties)
3. Move items into initial groups based on close relationships
4. Place items in only one task group initially

#### Second Pass Assessment
- Fix task groups with more than 10 items
- Address navigation pages with too many groups
- Ensure task group titles reflect group content
- Resolve items that fit in multiple task groups
- Handle generic items that don't fit anywhere specific

### Quality Indicators
- Task groups clearly convey where to find resources
- Framework page titles accurately reflect all content
- Titles clearly identify content using correct phrase types
- Moderate number of task groups and items per group
- Framework pages are uncluttered and easy to scan
- Articles promote teachable path with logical progression
- Advanced articles come after basic articles
- Task group abstracts are 1-2 sentences maximum
- Items within task groups follow specific order (articles first, then symbols)

### Curation Success Metrics
- Easy to find resources
- Arrangement tells you something about framework/class usage
- Task groups facilitate navigation and communicate available features
- Titles hint at types of tasks developer might perform
- Content organization supports both learning and resource discovery

# 4. Style and Formatting Guidelines

## 4.1 Voice and Tense Standards

### 4.1.1 Active Voice Requirements
- Write in active voice to emphasize specificity, immediacy, and clarity
- Identify the actor in sentences to create strong subject-verb connections
- Choose strong, specific verbs over general conceptual verbs
- Avoid passive voice constructions: "is used", "be constructed", "are multiplied"
- Rewrite passive sentences to make the actor the subject

**Server Documentation Examples:**
```
Passive: The request is processed by the server
Active: The server processes the request

Passive: Data is cached when the endpoint is called
Active: The system caches data when you call the endpoint
```

### 4.1.2 Present Tense Implementation
- Create documents in present tense for in-the-moment narrative effect
- Avoid future tense modifiers: "will", "could", "should", "might", "may"
- Replace "you will" and "you'll" with direct imperatives
- Describe what actually happens, not what might happen

**Server Context Applications:**
```
Instead of: "The API will return a response"
Use: "The API returns a response"

Instead of: "You'll configure the server settings"
Use: "Configure the server settings"
```

### 4.1.3 Second-Person Voice Standards
- Address developers directly using "you" for conversational tone
- Create approachable atmosphere for technical confidence
- Engage readers as peer-to-peer coaching
- Maintain factual, friendly, and inclusive tone

## 4.2 Language Conventions

### 4.2.1 Contraction Guidelines
- Use contractions for conversational tone in server documentation
- Standard contractions: aren't, can't, couldn't, didn't, doesn't, don't, hadn't, hasn't, haven't, isn't, there's, that's, they're
- Avoid: it'll, there'll, mustn't, there's no (rewrite instead)
- Never use double contractions: couldn't've, shouldn't've

### 4.2.2 Simplified Terminology
- Replace complex phrases with simpler alternatives
- Key server documentation replacements:
  - "execute/executing" → "run/running" or "invoke/invoking"
  - "utilize" → "use"
  - "in order to" → "to"
  - "prior to" → "before"
  - "subsequent to" → "after"
  - "activate/deactivate" → "turn on/turn off"
  - "enable/disable" → "turn on/turn off"

### 4.2.3 Redundancy Elimination
- Remove redundant phrases: "create a new", "input into", "connect together"
- Avoid archaic terms: "aforementioned", "hereby", "wherein", "shall"
- Eliminate meaningless words: "currently", "appropriate", "thus", "shall"

## 4.3 Grammar and Mechanics

### 4.3.1 Abbreviations and Acronyms
- Spell out first occurrence: "Application Programming Interface (API)"
- Use all caps for file types: "JSON file", "XML data"
- Style filename extensions in code font: `.json`, `.xml`, `.yaml`
- Don't use Latin abbreviations: use "for example" not "e.g."
- Form plurals without apostrophes: "APIs", "URLs"

### 4.3.2 Punctuation Standards
- **Sentence fragments**: All sentence fragments in documentation must end with periods for consistency and readability.
- Use Oxford comma in lists: "HTTP, HTTPS, and WebSocket protocols".
- Capitalize first word after colon if complete sentence.
- Precede all lists with colons.
- Use en dash for ranges: "2020–2021", "ports 8080–8090".
- Use em dash with spaces for interruptions: "The server — when properly configured — handles requests efficiently".

> **Critical Rule**: Every sentence fragment in bullet points, parameter descriptions, and abstracts must end with a period.

### 4.3.3 Spelling and Style
- Use American English spelling: "color" not "colour", "authorize" not "authorise"
- Avoid Latin abbreviations in favor of English equivalents
- Consult Merriam-Webster's Collegiate Dictionary for standard spellings

## 4.4 Typography and Code Formatting

### 4.4.1 Font Conventions
- **Body text**: Framework names, interface controls, paragraphs
- **Code font**: All executable program parts, user/program values, filenames, paths
- **Italics**: Mathematical variables, emphasis (use sparingly)
- **Bold**: Titles, headings, inline headings only

### 4.4.2 Code Font Applications

| Content Type | Example |
|--------------|---------|
| Code symbols | `attributes`, `methods`, `functions`, `properties` |
| System elements | `config.json`, `/usr/local/bin`, `environment.plist` |
| User input | `curl -X GET https://api.example.com` |
| Placeholder text | `Replace {serverName} with actual server name` |
| URLs | `https://api.example.com/v1/users` |

### 4.4.3 Code Formatting Rules
- Apply body text to punctuation following code font unless part of computer element
- Don't pluralize symbol names in code font
- Don't use code font in titles, abstracts, section headings, figure captions

## 4.5 Content Organization

### 4.5.1 List Formatting
- **Bulleted lists**: Related items in any order, minimum two items
- **Numbered lists**: Sequential steps or processes
- **Term definition lists**: Symbol descriptions, parameter explanations
- Precede all lists with colon-terminated introductory statement
- Use parallel phrasing within lists
- Capitalize first word of each list item

### 4.5.2 Table Standards
- Maximum four columns for mobile readability
- Minimum two content rows plus headers
- Use sentence-style capitalization for headers
- Keep descriptions to single sentences or fragments
- Reference tables as "following table" or "previous table"
- Don't number or caption tables

### 4.5.3 Link Implementation
- Link each instance of symbol names using double backticks: ``ServerManager``
- Use `<doc:filename>` syntax for internal documentation links
- Include section references: `<doc:api-guide#Authentication>`
- Link to symbols with path notation: ``HTTPServer/start()``

## 4.6 Technical Elements

### 4.6.1 Date and Time Formatting
- Spell out months and days when possible
- Use ordinal numbers for centuries: "21st century"
- Format ranges with "through" or en dash: "May through July" or "May–July"
- Don't use ordinal numbers in full dates: "August 12" not "August 12th"
- Use 24-hour format examples: "HH:MM", "HH:MM:SS"

### 4.6.2 Units of Measure
- Use numbers for all measurements: "3.6 GHz", "40 Gbit/s"
- Insert space between value and unit except degrees/percentages: "90°", "72%"
- Hyphenate spelled-out compound adjectives: "27-inch display"
- Don't hyphenate symbol abbreviations: "20 nA battery"
- Use lowercase 'x' for dimensions: "1920 x 1080", "5120 x 2880"

### 4.6.3 Command Line Standards
- Use code blocks for complete UNIX commands
- Include command prompt in examples: `% ls -la`
- Start with default prompt symbol followed by space
- Style commands, options, and paths in code font
- Refer to filesystem locations as "directories" not "folders"
- Use forward slashes for path separators: `/usr/local/bin`

## 4.7 Accessibility and Inclusivity

### 4.7.1 Alternative Text Requirements
- Begin with article and noun phrase: "A screenshot showing..."
- Describe image content and function concisely
- Use regular text with standard punctuation
- Don't repeat surrounding text information
- Describe components left-to-right or top-to-bottom for multi-image figures

### 4.7.2 Inclusive Language Standards
- Replace potentially exclusive terms:
  - "kill/terminate process" → "quit process"
  - "master/slave" → "primary/secondary"
  - "trigger" → "initiate/launch/start"
  - "whitelist/blacklist" → "allowlist/blocklist"
- Use "people" instead of "users" when referring to humans
- Consider alternatives to "parent/child": "container/subview", "root/subdirectory"

## 4.8 Legal and Standards Compliance

### 4.8.1 Terminology Guidelines
- Avoid absolute terms without justification: "always", "never", "must"
- Replace "should" with imperative statements
- Use "preferred" instead of "best" for neutral positioning
- Provide justification when using "don't" or "avoid"
- Replace "currently" unless explicitly comparing timeframes

### 4.8.2 Boolean Value Standards
- Use correct form: "A Boolean value that indicates whether..."
- Don't use: "A Boolean value indicating if..."
- For inequality operators: "Returns a Boolean value that indicates whether two values are not equal"
- Don't contract "are not" to "aren't" in Boolean descriptions

### 4.8.3 Actor Identification
- Use standard wording to identify action performers
- Avoid passive syntax that hides responsibility
- Clearly specify system, framework, or user as actor

**Examples:**
```
Passive: "When Mac support is enabled, frameworks are excluded"
Active: "When you enable Mac support, Xcode excludes incompatible frameworks"
```

## 4.9 Media and Interactive Elements

### 4.9.1 Figure Guidelines
- Place figures after introductory text with context
- Use colon when introductory sentence immediately precedes figure
- Don't number or caption figures in developer documentation
- Size figures to 735-pixel width with 4:3 aspect ratio preference
- Cross-reference by linking to section headings, not figures directly

### 4.9.2 Video Standards
- Use MP4 format only with 16:9 or 4:3 aspect ratio
- Limit duration to under 5 seconds
- Include poster image for all videos
- Compress using approved tools for web optimization
- Provide accessibility features: captions, transcripts, audio descriptions

### 4.9.3 Keyboard Shortcut Formatting
- Use body text styling for key names (no bold, italics, or code font)
- Capitalize key names: "Command", "Option", "Shift"
- Use hyphens for combination keystrokes: "Control-Shift-N"
- Order modifier keys: Control, Option, Shift, Command
- Use en dashes for two-word key combinations: "Option–Right Bracket"

## 4.10 Aside and Callout Standards

### 4.10.1 Aside Types and Usage
- **Note**: Ancillary but relevant information
- **Important**: Information requiring strict attention
- **Warning**: Critical information to prevent crashes or data loss
- **Tip**: Task-specific guidance for developers

### 4.10.2 Aside Formatting
- Place in context where information is needed
- Use sparingly (maximum two per document)
- Limit to few sentences or short paragraph
- Don't include lists, images, or code blocks
- Don't stack multiple asides consecutively

**Syntax:**
```
> Note: The specification doesn't support nested lists.
> Important: Set supported device types before building.
```

## 4.11 Server-Specific Applications

### 4.11.1 API Documentation Standards
- Use active voice for endpoint descriptions
- Present tense for request/response behavior
- Code font for HTTP methods, status codes, headers
- Consistent parameter documentation format
- Clear error message formatting

### 4.11.2 Configuration Documentation
- Step-by-step numbered lists for setup procedures
- Code blocks for configuration file examples
- Consistent environment variable formatting
- Clear directory structure representations

### 4.11.3 Protocol Documentation
- Precise technical language for specifications
- Consistent formatting for message structures
- Clear state transition descriptions
- Standardized error condition documentation

# 5. Dictionary and Terminology Reference

## 5.1 Abbreviations and Acronyms

### Core Development Acronyms
- **API**: application programming interface
- **ASCII**: American Standard Code for Information Interchange
- **JSON**: JavaScript Object Notation
- **HTTP**: Hypertext Transfer Protocol
- **HTTPS**: HTTP Secure
- **TCP**: Transmission Control Protocol
- **UDP**: User Datagram Protocol
- **TCP/IP**: Transmission Control Protocol/Internet Protocol
- **URL**: uniform resource locator
- **UUID**: universally unique identifier
- **UTF**: Unicode Transformation Format
- **XML**: Extensible Markup Language
- **SSL**: Secure Sockets Layer (deprecated, use TLS)
- **TLS**: Transport Layer Security

### System and Architecture
- **CPU**: central processing unit
- **RAM**: random-access memory
- **ROM**: read-only memory
- **I/O**: input/output
- **BSD**: Berkeley Software Distribution
- **POSIX**: Portable Operating System Interface
- **RPC**: remote procedure call
- **IPC**: interprocess communication

### Data and Encoding
- **B**: byte
- **KB**: kilobyte
- **MB**: megabyte
- **GB**: gigabyte
- **TB**: terabyte
- **BOM**: byte order mark
- **Base64**: binary-to-text encoding scheme

## 5.2 Numbers and Symbols

### Programming Symbols
- **0x**: hexadecimal number prefix (0xD8AF)
- **==**: equal-to operator
- **!=**: not-equal-to operator
- **<**: less-than operator
- **>**: greater-than operator
- **<=**: less-than-or-equal-to operator
- **>=**: greater-than-or-equal-to operator
- **&**: ampersand (logical AND, reference operator)
- **|**: vertical bar (logical OR operator)
- **!**: logical NOT operator
- **~**: tilde (bitwise NOT, home directory)
- **#**: hash symbol (preprocessor directive, comment)
- **@**: at sign (decorator, annotation)
- **%**: percent sign (modulo operator)
- **^**: caret (XOR operator, exponentiation)
- **\**: backslash (escape character, path separator)
- **/**: slash (division operator, path separator)

### Coordinate and Mathematical
- **(0,0)**: coordinate format (x,y with no space after comma)
- **±**: plus-or-minus sign
- **≈**: approximately-equal sign
- **≠**: not-equal sign
- **≤**: less-than-or-equal sign
- **≥**: greater-than-or-equal sign

## 5.3 Framework Terminology

### Combine Framework (Event Processing)
- **Publisher**: source of elements in declarative event processing
- **Subscriber**: receiver of elements from publishers
- **Operator**: method creating subscribers from publishers
- **Element**: item published by publisher, received by subscriber
- **Completion**: value indicating publishing end state (.success/.failure)
- **Demand**: subscriber's willingness to receive elements
- **Cancellable**: type that can cancel publishing
- **Upstream/Downstream**: directional flow of elements

### Security Terminology
- **Certificate**: document containing public key with assertions
- **Certificate Authority**: entity issuing certificates
- **Digital Identity**: certificate plus associated private key
- **Cleartext**: unencrypted text (preferred over "plaintext")
- **Ciphertext**: encrypted text
- **Hash**: fixed-size output from hash function
- **Keychain**: cryptographic storage for secrets
- **Sandbox**: access control technology containing app damage
- **TLS**: Transport Layer Security (modern replacement for SSL)

## 5.4 Core Swift Terminology

### Language Constructs
- **Function**: block of code with `func` keyword, defined at top level
- **Method**: function defined within scope of a type
- **Closure**: self-contained blocks of functionality
- **Structure**: general-purpose constructs (use "structure", not "struct")
- **Protocol**: blueprint of methods, properties, requirements
- **Conform**: when type satisfies protocol requirements
- **Extension**: adds functionality to existing types

### Memory and Reference Management
- **ARC**: Automatic Reference Counting
- **Reference**: pointer to memory location
- **Value**: data passed to parameter
- **Parameter**: named value in function signature
- **Argument**: actual value passed (UNIX/C contexts only)

### Concurrency and Threading
- **Asynchronous**: allows non-blocking execution with `async` keyword
- **Thread**: execution context for code
- **Queue**: ordered collection managing task execution
- **Synchronous**: blocking execution until completion
- **Concurrent**: multiple operations executing simultaneously

### Data Types and Collections
- **Array**: ordered collection of elements
- **Dictionary**: collection of key-value pairs
- **Set**: unordered collection of unique elements
- **String**: sequence of characters
- **Integer**: whole number data type
- **Boolean**: true/false value type
- **Optional**: type that can contain value or nil

## 5.5 Universal Development Terms

### Architecture Patterns
- **Client/Server**: distributed computing model
- **MVC**: Model-View-Controller design pattern
- **API**: interface for software component interaction
- **Framework**: reusable software platform
- **Library**: collection of precompiled routines
- **Module**: self-contained software component

### Development Process
- **Build**: process of compiling source code
- **Debug**: process of finding and fixing errors
- **Deploy**: process of making software available
- **Version**: specific release of software
- **Dependency**: external component required by software
- **Repository**: storage location for source code

### Network and Communication
- **Endpoint**: communication point in network
- **Request**: message sent to server
- **Response**: message returned from server
- **Timeout**: maximum time to wait for operation
- **Latency**: delay in network communication
- **Bandwidth**: data transfer capacity

### Error Handling
- **Exception**: runtime error condition
- **Error**: problem preventing normal execution
- **Failure**: unsuccessful operation result
- **Validation**: process of checking data correctness
- **Logging**: recording of system events

### Performance and Optimization
- **Cache**: temporary storage for frequently accessed data
- **Buffer**: temporary storage area for data transfer
- **Throughput**: amount of work completed per time unit
- **Scalability**: ability to handle increased load
- **Optimization**: process of improving efficiency

### File System and Storage
- **Directory**: container for organizing files (system level)
- **Folder**: user-visible container for files
- **Path**: location specification for file or directory
- **Extension**: suffix indicating file type
- **Binary**: executable file format
- **Archive**: compressed file collection

### Data Processing
- **Parse**: analyze string or data structure
- **Serialize**: convert object to storable format
- **Deserialize**: convert stored format back to object
- **Encode**: convert data to specific format
- **Decode**: convert encoded data back to original
- **Transform**: convert data from one format to another

### Security and Access Control
- **Authentication**: process of verifying identity
- **Authorization**: process of granting permissions
- **Encryption**: process of encoding data for security
- **Decryption**: process of decoding encrypted data
- **Token**: piece of data representing authorization
- **Session**: period of user interaction with system.

---

## Conclusion

This Swift Server Documentation Guide provides comprehensive standards for creating consistent, high-quality documentation for server-side Swift development. By following these guidelines, documentation authors can ensure their content is accurate, inclusive, clear, and consistent across all server-side Swift projects.

### Key Principles Summary

1. **Accuracy**: Maintain impeccable standards as the source of truth for server-side Swift development.
2. **Inclusivity**: Write for diverse audiences with varying experience levels.
3. **Clarity**: Use direct communication with the fewest, simplest words.
4. **Consistency**: Follow established standards for a reliable, recognizable voice.
