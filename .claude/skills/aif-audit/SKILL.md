# Security Audit — проверка библиотеки на закладки

Проверка fork-библиотеки tinkoff-invest-api-v2-php на вредоносный код, утечки токенов и скрытые модификации.

## Режимы запуска

- `/aif-audit` — полный аудит (diff реестра + pattern scan + ручной анализ)
- `/aif-audit snapshot` — сохранить текущее состояние как baseline
- `/aif-audit diff` — только сравнение с реестром
- `/aif-audit scan` — только pattern-проверки
- `/aif-audit upstream` — полный цикл: забрать изменения upstream → аудит новых файлов

## Workflow

### Режим: полный аудит (по умолчанию)

**Step 1: Запуск автоматических проверок**

```bash
cd <project_root>
.ai-factory/audit/audit.sh
```

Скрипт выполняет:
1. **Registry diff** — сравнивает SHA-256 хэши всех файлов с сохранённым реестром
2. **Pattern scan** — ищет опасные паттерны в коде (7 категорий проверок)

**Step 2: Ручной анализ критических файлов**

После автоматических проверок ОБЯЗАТЕЛЬНО прочитать и проанализировать:

1. `src/ClientConnection.php` — проверить:
   - Хостнеймы API (должны быть ТОЛЬКО `invest-public-api.tbank.ru` и `sandbox-invest-public-api.tbank.ru`)
   - SSL-конфигурацию (не отключён ли SSL, правильный ли путь к сертификату)
   - Нет ли дополнительных метаданных в `update_metadata`, кроме `authorization` и `x-app-name`

2. `src/TinkoffClientsFactory.php` — проверить:
   - Токен используется ТОЛЬКО в `getBaseConnectionOptions()`
   - Нет посторонних методов, которые обращаются к `$_api_token`
   - Все клиенты создаются через `ClientConnection::getHostname()` (а не через хардкод)

3. `etc/*.pem` — проверить:
   - Сертификат действителен: `openssl x509 -in etc/invest-public-api_tbank_ru.pem -text -noout`
   - CN/SAN соответствует домену API
   - Issuer — ожидаемый CA

**Step 3: Анализ изменённых/новых файлов**

Для каждого файла со статусом MODIFIED или NEW из registry diff:
- Прочитать файл целиком
- Проверить на каждую категорию угроз из таблицы ниже
- Вывести резюме: SAFE / SUSPICIOUS / DANGEROUS

**Step 4: Отчёт**

Вывести итоговый отчёт:
```
## Audit Report — [дата]

### Автоматические проверки
- Registry diff: X new, Y modified, Z deleted
- Pattern scan: X critical, Y warnings

### Ручной анализ
- ClientConnection.php: [OK / FINDING]
- TinkoffClientsFactory.php: [OK / FINDING]
- SSL certificates: [OK / FINDING]

### Изменённые файлы
| Файл | Статус | Вердикт |
|------|--------|---------|
| ... | MODIFIED | SAFE |

### Итог: [PASSED / FAILED]
```

---

### Режим: snapshot

Сохраняет текущее состояние всех файлов как доверенный baseline.

```bash
.ai-factory/audit/audit.sh --snapshot
```

Запускать ПОСЛЕ того, как вы вручную убедились в безопасности текущего состояния кода. Записывает SHA-256 хэши всех файлов в `.ai-factory/audit/registry.json`.

---

### Режим: upstream (полный цикл обновления)

**Step 1: Проверить текущее состояние**
```bash
git status
git remote -v
```

**Step 2: Забрать изменения из upstream**
```bash
# Если upstream remote не настроен:
git remote add upstream https://github.com/metaseller/tinkoff-invest-api-v2-php.git

git fetch upstream
git log HEAD..upstream/main --oneline   # посмотреть новые коммиты
```

**Step 3: Показать пользователю список изменений ДО мержа**
```bash
git diff HEAD..upstream/main --stat
git diff HEAD..upstream/main -- src/ etc/ composer.json
```

Показать пользователю и спросить подтверждение через AskUserQuestion:
```
Upstream содержит N новых коммитов. Изменены файлы:
[список]

Выполнить merge и запустить аудит?
```

**Step 4: Merge + аудит**
```bash
git merge upstream/main
.ai-factory/audit/audit.sh
```

**Step 5: Ручной анализ** (как в полном аудите Step 2-3)

**Step 6: Обновить snapshot при успехе**

Если аудит пройден — спросить пользователя, обновить ли baseline:
```bash
.ai-factory/audit/audit.sh --snapshot
```

---

## Таблица угроз

| Категория | Паттерны | Где критично |
|-----------|----------|-------------|
| Выполнение кода | `eval`, `exec`, `system`, `passthru`, `proc_open`, `shell_exec` | Везде |
| Обфускация | `base64_decode`, `gzinflate`, `str_rot13`, hex-escape | Везде |
| Сетевые вызовы | `curl_*`, `file_get_contents(http)`, `fsockopen`, `stream_socket_client` | Вне gRPC |
| Утечка токена | `$_api_token` за пределами Factory/Connection | Везде |
| Подмена хоста | Неизвестные хостнеймы в `ClientConnection` | Критически |
| Запись файлов | `fwrite`, `file_put_contents` | В SDK-коде |
| SSL bypass | `GRPC_SSL_DONT_REQUEST`, отключение проверки сертификата | Transport |

## Файлы

- `.ai-factory/audit/audit.sh` — скрипт автоматических проверок
- `.ai-factory/audit/registry.json` — реестр хэшей (baseline)
- `.ai-factory/audit/certs-fingerprints.json` — отпечатки SSL-сертификатов
- `.ai-factory/audit/audit-report.txt` — последний отчёт