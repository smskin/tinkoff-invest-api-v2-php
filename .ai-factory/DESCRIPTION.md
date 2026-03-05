# Project: Tinkoff Invest API v2 PHP SDK

## Overview
Fork of the unofficial PHP SDK for T-Invest (Tinkoff Investments) API v2. Provides PHP client wrappers over gRPC services for interacting with the T-Invest trading platform. The SDK includes auto-generated protobuf models, client factory, data providers, helper utilities, and DTO classes.

## Core Features
- gRPC client factory (`TinkoffClientsFactory`) for all T-Invest API services
- Auto-generated protobuf models from official invest-contracts (v1.44)
- Data providers for instruments, market data, and portfolio
- Helper classes for price/quantity conversions (Quotation, MoneyValue)
- DTO classes for Price and Quantity with arithmetic operations
- SSL certificate management for API connectivity

## Tech Stack
- **Language:** PHP 7.4+
- **Protocol:** gRPC (ext-grpc ^1.74)
- **Serialization:** Protocol Buffers (google/protobuf ^3.25.1)
- **Extensions:** ext-grpc, ext-bcmath, ext-json
- **Type:** Composer library (not a framework application)

## Architecture
See `.ai-factory/ARCHITECTURE.md` for detailed architecture guidelines.
Pattern: Layered Library

## API References
- Official API docs: https://developer.tbank.ru/invest/intro/intro/
- Original library: https://github.com/metaseller/tinkoff-invest-api-v2-php
- Fork repository: https://github.com/smskin/tinkoff-invest-api-v2-php
- Proto contracts source: https://opensource.tbank.ru/invest/invest-contracts/
