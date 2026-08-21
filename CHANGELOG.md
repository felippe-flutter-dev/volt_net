# Changelog

Todas as mudanças relevantes do projeto `volt_net` são registradas neste arquivo.

## 2.1.1 (Pending)

### Added

- **Stale-While-Revalidate**: nova política configurável por `Volt.initialize(staleWhileRevalidate: true)` para entregar o cache imediatamente e disparar a revalidação online em seguida.
- **Callback `onUpdate`**: o método `GetRequest.get()` pode emitir a resposta fresca da API depois que o cache já foi entregue à UI.
- **Promoção automática para L1**: respostas atualizadas pela rede são persistidas no cache em disco e promovidas para a memória RAM quando o tipo de cache permite.
- **Limpeza física por TTL**: entradas expiradas do cache SQLite são removidas do armazenamento quando detectadas durante a leitura.
- **Roadmap público**: adicionada a documentação [`ROADMAP.md`](ROADMAP.md) com os marcos atuais e planejados.
- **Documentação REST ampliada**: incluídos exemplos de configuração no `main.dart`, GET, POST, PUT/UPDATE e DELETE, além de diagramas Mermaid.

### Changed

- **GET network-first**: o método `GetRequest.get()` agora consulta a rede por padrão. A leitura antecipada do cache precisa ser solicitada com `readCache: true`.
- **GET stale-while-revalidate**: quando `readCache: true` e `staleWhileRevalidate: true` estão ativos, a resposta cacheada não encerra o fluxo; a API é consultada e o dado atualizado é encaminhado por `onUpdate`.
- **GET bytes**: `getBytes()` também permite controlar explicitamente `readCache` e `ttl`.
- **Cache por nível**: `CacheType.memory` não consulta mais o SQLite, evitando que uma entrada persistida seja recuperada quando a chamada pediu somente L1.
- **Documentação**: o README passou a refletir os contratos públicos atuais e registra que PATCH ainda não é uma API disponível. Alterações parciais devem usar PUT apenas quando o backend aceitar essa semântica; suporte nativo a PATCH permanece no roadmap.

### Fixed

- **Dados desatualizados no feed**: corrigido o comportamento em que uma entrada válida permanecia sendo exibida até o fim do TTL sem nova consulta à rede.
- **Persistência de entradas expiradas**: corrigido o acúmulo de registros expirados no cache em disco após uma leitura com TTL vencido.
- **Regressões de cache**: adicionados testes para confirmar entrega imediata do cache, revalidação online, callback de atualização e remoção física no SQLite.

## 2.0.0 - 2026-03-04

### Added

- **Full REST Support**: implementação de `PutRequest` e `DeleteRequest` com resiliência e suporte à sincronização offline.
- **Enterprise Resilience**: `resilientBatch` em `PostRequest`, com rollback automático e suporte a idempotency key.
- **Advanced Offline Sync**: `SyncQueueManager` passou a persistir operações `PUT` e `DELETE`.
- **Multipart Media Sync**: suporte a arquivos na fila offline usando `VoltFile`.
- **VoltInterceptor**: sistema de interceptors para modificação global de requisições, respostas e erros.
- **New Models**: `VoltFile` e `ResultModel<T>` com parsing em isolate.
- **Testing Suite**: ampliação da cobertura com testes de integração e casos extremos.
- **Utilities**: adição de `Debouncer` para gerenciamento de eventos de alta frequência.

### Changed

- **BREAKING**: remoção do nome legado `EcoloteNetwork` em favor de `VoltNet`.
- **BREAKING**: refatoração de `CacheManager`, `SyncQueueManager` e classes de request para injeção por construtor.
- **Error Mapping**: `ThrowHttpException` passou a mapear exceções nativas em subclasses tipadas de `VoltNetException`.
- **Deterministic Cache**: substituição de `.hashCode` por chaves baseadas em strings resistentes a colisões.
- **Standardization**: padronização dos logs e mensagens internas em inglês.
- **URL Building**: uso de `Uri.resolve()` para construção de URLs absolutas.

### Fixed

- Tratamento de corpos `null` e vazios em `ResultApi`.
- Persistência de campos multipart na fila de sincronização offline.
- Confiabilidade do parsing em isolate para JSON complexo ou profundamente aninhado.
- Erros de compilação em `CacheManager.clearAll`.
