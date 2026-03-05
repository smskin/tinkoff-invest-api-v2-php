# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Fork of the unofficial PHP SDK for T-Invest (Tinkoff Investments) API v2. Provides PHP gRPC client wrappers for the T-Invest trading platform.

- Original: https://github.com/metaseller/tinkoff-invest-api-v2-php
- API docs: https://developer.tbank.ru/invest/intro/intro/
- Proto contracts: https://opensource.tbank.ru/invest/invest-contracts/

## Build & Install

```bash
composer install
```

Requires PHP 7.4+ with extensions: `ext-grpc` (^1.74), `ext-bcmath`, `ext-json`.

Regenerating protobuf models from proto files (rarely needed):
```bash
protoc --proto_path=library/src/docs/contracts/ --php_out=src/models/ --grpc_out=src/models/ --plugin=protoc-gen-grpc=./grpc_php_plugin library/src/docs/contracts/*
```

No test suite exists. Run examples to verify functionality:
```bash
php examples/example1.php
```

## Architecture

**Never edit files in `src/models/`** — they are auto-generated from `.proto` files in `library/src/docs/contracts/`.

### Layer structure (dependencies flow downward):

1. **Models** (`src/models/Tinkoff/Invest/V1/`) — auto-generated protobuf message/service classes. Namespace: `Tinkoff\Invest\V1\`
2. **Transport** (`src/ClientConnection.php`) — hostname, SSL certs, gRPC credentials. Sandbox mode via `TINKOFF_API2_SANDBOX_MODE` env var
3. **Factory** (`src/TinkoffClientsFactory.php`) — creates and caches all gRPC service clients as lazy singletons. `ModelTrait` enables property-style access (`$factory->usersServiceClient` → calls `getUsersServiceClient()`)
4. **Helpers/DTOs** (`src/helpers/`, `src/dto/`) — conversion between protobuf types (`Quotation`, `MoneyValue`) and PHP floats/ints
5. **Providers** (`src/providers/`) — high-level API on top of the factory (instruments lookup with caching, market data, portfolio)

### Key patterns

- **Quotation/MoneyValue representation**: T-Invest API uses `units` (int64) + `nano` (int32, 10^-9) format. `QuotationHelper` converts between this and PHP floats. `Quantity`/`Price` DTOs wrap these conversions with precision handling (9 decimal places, multiplier 10^9).

- **Service clients**: `TinkoffClientsFactory` wraps 10 gRPC service clients (Instruments, MarketData, MarketDataStream, Operations, OperationsStream, Orders, OrdersStream, Sandbox, StopOrders, Users). Each getter follows the same pattern: returns a singleton unless custom `$extra_options` or `$channel` is passed.

- **Instrument types**: The API has multiple instrument model classes (`Share`, `Bond`, `Etf`, `Future`, `Currency`, `Instrument`). `InstrumentsHelper::isInstrumentModelValid()` validates any of these. Bond pricing uses nominal-based calculation; futures use min price increment ratio.

- **SSL certificates**: `etc/` contains custom certs (Russian Ministry of Digital Development CA chain). `ClientConnection` reads `etc/invest-public-api_tbank_ru.pem` for SSL. Consumers may need `putenv("SSL_CERT_FILE=vendor/metaseller/tinkoff-invest-api-v2-php/etc/roots.pem")`.

### Namespace mapping (from composer.json)
- `Metaseller\TinkoffInvestApi2\` → `src/`
- `Tinkoff\Invest\V1\` → `src/models/Tinkoff/Invest/V1/` (auto-generated)
- `GPBMetadata\` → `src/models/GPBMetadata/` (auto-generated)

## Security Audit

This is a fork of an external library. Use `/aif-audit` to check for backdoors after pulling upstream changes.

```bash
# Pattern scan (no registry needed)
.ai-factory/audit/audit.sh --scan-only

# Save current state as trusted baseline
.ai-factory/audit/audit.sh --snapshot

# Full audit (registry diff + pattern scan)
.ai-factory/audit/audit.sh
```

Upstream update workflow: `/aif-audit upstream`
