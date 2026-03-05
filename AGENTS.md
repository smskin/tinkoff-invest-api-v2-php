# AGENTS.md

> Project map for AI agents. Keep this file up-to-date as the project evolves.

## Project Overview
Fork of the unofficial PHP SDK for T-Invest API v2. Provides gRPC client wrappers and protobuf models for interacting with the Tinkoff Investments trading platform.

## Tech Stack
- **Language:** PHP 7.4+
- **Protocol:** gRPC
- **Serialization:** Protocol Buffers
- **Type:** Composer library

## Project Structure
```
src/
  ClientConnection.php       # gRPC connection configuration (hostname, SSL, credentials)
  TinkoffClientsFactory.php  # Factory creating all gRPC service clients
  ModelTrait.php             # Trait for model serialization
  dto/                       # Data Transfer Objects (Price, Quantity)
  exceptions/                # SDK exceptions (RequestException, ValidateException, etc.)
  helpers/                   # Utility classes (QuotationHelper, NumbersHelper, etc.)
  providers/                 # High-level data providers (Instruments, MarketData, Portfolio)
  models/                    # AUTO-GENERATED protobuf models — DO NOT EDIT
    GPBMetadata/             # Protobuf metadata classes
    Google/                  # Google protobuf types
    Tinkoff/Invest/V1/       # T-Invest API v1 message and service classes
library/
  src/docs/contracts/        # Proto contract files (source for model generation)
etc/                         # SSL certificates for API connection
examples/                    # Usage examples (example1.php — example6.php)
```

## Key Entry Points
| File | Purpose |
|------|---------|
| src/TinkoffClientsFactory.php | Main entry point — creates all API service clients |
| src/ClientConnection.php | Connection config (hostname, SSL certs, auth token) |
| composer.json | Package definition and autoload configuration |

## Documentation
| Document | Path | Description |
|----------|------|-------------|
| README | README.md | Installation guide and usage examples |

## AI Context Files
| File | Purpose |
|------|---------|
| AGENTS.md | This file — project structure map |
| .ai-factory/DESCRIPTION.md | Project specification and tech stack |
| .ai-factory/ARCHITECTURE.md | Architecture decisions and guidelines |
