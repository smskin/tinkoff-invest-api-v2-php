# Architecture: Layered Library

## Overview
This project follows a layered library architecture — a pattern optimized for SDK/wrapper libraries that provide a PHP interface over an external gRPC API. The library organizes code into clear horizontal layers: auto-generated protocol models at the base, connection/transport infrastructure, client factory as the main entry point, and higher-level abstractions (providers, DTOs, helpers) on top.

This pattern was chosen because the project is a thin wrapper library, not an application with complex business logic. The primary goals are: clear separation between generated and hand-written code, simple API surface for consumers, and maintainability when upstream contracts change.

## Decision Rationale
- **Project type:** Composer library (PHP SDK for gRPC API)
- **Tech stack:** PHP 7.4+, gRPC, Protocol Buffers
- **Key factor:** Library nature — no application-level concerns (routing, UI, database), focus on wrapping external API

## Folder Structure
```
src/
  models/                    # Layer 0: AUTO-GENERATED protobuf models (DO NOT EDIT)
    GPBMetadata/             #   Protobuf metadata
    Google/                  #   Google protobuf types
    Tinkoff/Invest/V1/       #   T-Invest API message & service client classes
  ClientConnection.php       # Layer 1: Transport — hostname, SSL, credentials
  TinkoffClientsFactory.php  # Layer 2: Factory — creates and exposes all gRPC service clients
  ModelTrait.php             # Layer 2: Serialization trait for models
  exceptions/                # Layer 2: SDK exception hierarchy
    BaseSDKException.php
    RequestException.php
    ValidateException.php
    InstrumentNotFoundException.php
  helpers/                   # Layer 3: Utilities for data conversion
    QuotationHelper.php      #   Quotation ↔ float conversions
    NumbersHelper.php        #   Numeric formatting
    ArrayHelper.php          #   Array utilities
    InstrumentsHelper.php    #   Instrument lookup helpers
  dto/                       # Layer 3: Value objects for price/quantity
    Quantity.php             #   Base DTO with units/nano/decimal/integer representations
    Price.php                #   Extends Quantity with currency support
  providers/                 # Layer 4: High-level data providers (convenience API)
    BaseDataProvider.php     #   Abstract base with factory injection
    InstrumentsProvider.php  #   Instruments lookup and caching
    MarketDataProvider.php   #   Market data access
    PortfolioProvider.php    #   Portfolio operations
```

## Dependency Rules

Dependencies flow strictly downward through the layers:

- **Layer 0 (Models)** → nothing (auto-generated, self-contained)
- **Layer 1 (Transport)** → Layer 0 (uses model constants)
- **Layer 2 (Factory/Exceptions)** → Layer 1 + Layer 0 (creates clients with transport config)
- **Layer 3 (Helpers/DTOs)** → Layer 0 (converts between protobuf types and PHP primitives)
- **Layer 4 (Providers)** → Layer 2 + Layer 3 + Layer 0 (uses factory, helpers, and models)

Allowed and forbidden:
- ✅ Providers depend on Factory, Helpers, DTOs, and Models
- ✅ DTOs/Helpers depend on Models (protobuf types)
- ✅ Factory depends on Transport and Models
- ❌ Models MUST NOT depend on anything in the SDK (they are auto-generated)
- ❌ Transport MUST NOT depend on Providers, DTOs, or Helpers
- ❌ Helpers MUST NOT depend on Providers or Factory
- ❌ No circular dependencies between layers

## Layer Communication
- **Consumer → Factory:** User creates `TinkoffClientsFactory::create($token)`, gets access to all service clients via properties
- **Consumer → Providers:** User creates a provider with `InstrumentsProvider::create($factory)` for higher-level operations
- **Factory → gRPC clients:** Factory lazily instantiates service clients using `ClientConnection` for transport settings
- **Providers → Factory:** Providers use injected factory to call gRPC methods
- **DTOs ↔ Protobuf models:** DTOs wrap protobuf types (Quotation, MoneyValue) with conversion methods

## Key Principles
1. **Generated code is immutable** — never manually edit files in `src/models/`. Regenerate from proto contracts when API updates
2. **Factory is the main entry point** — all gRPC clients are accessed through `TinkoffClientsFactory`
3. **Providers are optional convenience** — consumers can use raw gRPC clients directly or use providers for common patterns
4. **DTOs bridge protobuf and PHP** — `Price` and `Quantity` handle the complexity of units/nano representation

## Code Examples

### Using the Factory (primary API)
```php
use Metaseller\TinkoffInvestApi2\TinkoffClientsFactory;
use Tinkoff\Invest\V1\GetInfoRequest;

$factory = TinkoffClientsFactory::create($token);

$request = new GetInfoRequest();
list($response, $status) = $factory->usersServiceClient->GetInfo($request)->wait();
```

### Using a Provider (convenience API)
```php
use Metaseller\TinkoffInvestApi2\providers\InstrumentsProvider;

$provider = InstrumentsProvider::create($factory);
// Provider handles request construction, error handling, and caching internally
```

### Working with DTOs
```php
use Metaseller\TinkoffInvestApi2\dto\Price;

// Create from protobuf MoneyValue
$price = Price::createFromMoneyValue($response->getPrice());

// Access in different formats
$decimal = $price->asDecimal();      // float
$integer = $price->asInteger();      // int (with precision)
$quotation = $price->asQuotation();  // Quotation protobuf
$money = $price->asMoneyValue();     // MoneyValue protobuf
```

## Anti-Patterns
- ❌ Do not manually edit files in `src/models/` — they will be overwritten on contract update
- ❌ Do not add business/application logic to this library — it is a transport/SDK layer
- ❌ Do not create direct gRPC channels outside `ClientConnection` — use the centralized transport config
- ❌ Do not add framework-specific code (Laravel, Symfony) — keep the library framework-agnostic
