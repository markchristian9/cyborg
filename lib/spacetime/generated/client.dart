// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:spacetimedb_sdk/codegen.dart';
import 'reducers.dart';
import 'reducer_args.dart';
import 'monster_kill.dart';
import 'monster_tick_timer.dart';
import 'world_player.dart';
import 'account_secret.dart';
import 'monster.dart';
import 'account.dart';
import 'session.dart';
import 'leaderboard_entry.dart';
import 'player_character.dart';

class SpacetimeDbClient {
  SpacetimeDbClient._({
    required this.connection,
    required this.subscriptions,
    required AuthTokenStore authStorage,
    required bool ssl,
  }) : _authStorage = authStorage,
       _ssl = ssl {
    reducers = Reducers(subscriptions.reducers, subscriptions.reducerEmitter);
  }

  final SpacetimeDbConnection connection;

  final SubscriptionManager subscriptions;

  final AuthTokenStore _authStorage;

  final bool _ssl;

  late final Reducers reducers;

  ReducerEmitter get reducerEmitter {
    return subscriptions.reducerEmitter;
  }

  Identity? get identity {
    return subscriptions.identity;
  }

  String? get address {
    return subscriptions.address;
  }

  String? get token {
    return connection.token;
  }

  bool get hasOfflineStorage {
    return subscriptions.hasOfflineStorage;
  }

  SyncState get syncState {
    return subscriptions.syncState;
  }

  Stream<SyncState> get onSyncStateChanged {
    return subscriptions.onSyncStateChanged;
  }

  Stream<MutationSyncResult> get onMutationSyncResult {
    return subscriptions.onMutationSyncResult;
  }

  void clearSyncErrors() {
    subscriptions.clearSyncErrors();
  }

  TableCache<MonsterKill> get monsterKill {
    return subscriptions.cache.getTableByTypedName<MonsterKill>('monster_kill');
  }

  TableCache<MonsterTickTimer> get monsterTickTimer {
    return subscriptions.cache.getTableByTypedName<MonsterTickTimer>(
      'monster_tick_timer',
    );
  }

  TableCache<WorldPlayer> get worldPlayer {
    return subscriptions.cache.getTableByTypedName<WorldPlayer>('world_player');
  }

  TableCache<AccountSecret> get accountSecret {
    return subscriptions.cache.getTableByTypedName<AccountSecret>(
      'account_secret',
    );
  }

  TableCache<Monster> get monster {
    return subscriptions.cache.getTableByTypedName<Monster>('monster');
  }

  TableCache<Account> get account {
    return subscriptions.cache.getTableByTypedName<Account>('account');
  }

  TableCache<Session> get session {
    return subscriptions.cache.getTableByTypedName<Session>('session');
  }

  TableCache<LeaderboardEntry> get leaderboardEntry {
    return subscriptions.cache.getTableByTypedName<LeaderboardEntry>(
      'leaderboard_entry',
    );
  }

  TableCache<PlayerCharacter> get playerCharacter {
    return subscriptions.cache.getTableByTypedName<PlayerCharacter>(
      'player_character',
    );
  }

  TableCache<LeaderboardEntry> get leaderboard {
    return subscriptions.cache.getTableByTypedName<LeaderboardEntry>(
      'leaderboard',
    );
  }

  Account? get myAccount {
    final cache = subscriptions.cache.getTableByTypedName<Account>(
      'my_account',
    );
    final iterator = cache.iter().iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  TableCache<PlayerCharacter> get myCharacters {
    return subscriptions.cache.getTableByTypedName<PlayerCharacter>(
      'my_characters',
    );
  }

  LeaderboardEntry? get myRank {
    final cache = subscriptions.cache.getTableByTypedName<LeaderboardEntry>(
      'my_rank',
    );
    final iterator = cache.iter().iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  Session? get mySession {
    final cache = subscriptions.cache.getTableByTypedName<Session>(
      'my_session',
    );
    final iterator = cache.iter().iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  static Future<SpacetimeDbClient> create({
    required String host,
    required String database,
    AuthTokenStore? authStorage,
    OfflineStorage? offlineStorage,
    OfflineQueuePolicy queuePolicy = const OfflineQueuePolicy(),
    bool ssl = false,
    ConnectionConfig config = const ConnectionConfig(),
  }) async {
    final storage = authStorage ?? InMemoryTokenStore();
    final savedToken = await storage.loadToken();
    final connection = SpacetimeDbConnection(
      host: host,
      database: database,
      initialToken: savedToken,
      ssl: ssl,
      config: config,
    );
    final subscriptionManager = SubscriptionManager(
      connection,
      offlineStorage: offlineStorage,
      queuePolicy: queuePolicy,
    );

    subscriptionManager.cache.registerDecoder<MonsterKill>(
      'monster_kill',
      MonsterKillDecoder(),
    );
    subscriptionManager.cache.registerDecoder<MonsterTickTimer>(
      'monster_tick_timer',
      MonsterTickTimerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<WorldPlayer>(
      'world_player',
      WorldPlayerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<AccountSecret>(
      'account_secret',
      AccountSecretDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Monster>(
      'monster',
      MonsterDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Account>(
      'account',
      AccountDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Session>(
      'session',
      SessionDecoder(),
    );
    subscriptionManager.cache.registerDecoder<LeaderboardEntry>(
      'leaderboard_entry',
      LeaderboardEntryDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PlayerCharacter>(
      'player_character',
      PlayerCharacterDecoder(),
    );

    subscriptionManager.cache.registerDecoder<LeaderboardEntry>(
      'leaderboard',
      LeaderboardEntryDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Account>(
      'my_account',
      AccountDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PlayerCharacter>(
      'my_characters',
      PlayerCharacterDecoder(),
    );
    subscriptionManager.cache.registerDecoder<LeaderboardEntry>(
      'my_rank',
      LeaderboardEntryDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Session>(
      'my_session',
      SessionDecoder(),
    );

    subscriptionManager.reducerRegistry.register(attackMonsterDef);
    subscriptionManager.reducerRegistry.register(changePasswordDef);
    subscriptionManager.reducerRegistry.register(createCharacterDef);
    subscriptionManager.reducerRegistry.register(deleteCharacterDef);
    subscriptionManager.reducerRegistry.register(ensureWorldPopulatedDef);
    subscriptionManager.reducerRegistry.register(enterWorldDef);
    subscriptionManager.reducerRegistry.register(leaveWorldDef);
    subscriptionManager.reducerRegistry.register(loginDef);
    subscriptionManager.reducerRegistry.register(logoutDef);
    subscriptionManager.reducerRegistry.register(moveToDef);
    subscriptionManager.reducerRegistry.register(registerAccountDef);
    subscriptionManager.reducerRegistry.register(reportProgressDef);
    subscriptionManager.reducerRegistry.register(selectCharacterDef);
    subscriptionManager.reducerRegistry.register(teleportToDef);

    final client = SpacetimeDbClient._(
      connection: connection,
      subscriptions: subscriptionManager,
      authStorage: storage,
      ssl: ssl,
    );

    subscriptionManager.onInitialConnection.listen((msg) async {
      await storage.saveToken(msg.token);
      connection.updateToken(msg.token);
    });

    if (offlineStorage != null) {
      await subscriptionManager.loadFromOfflineCache();
    }

    return client;
  }

  Future<void> connect({
    List<String>? initialSubscriptions,
    Duration subscriptionTimeout = const Duration(seconds: 10),
  }) async {
    await connection.connect().timeout(connection.config.connectTimeout);
    if (initialSubscriptions != null && initialSubscriptions.isNotEmpty) {
      await subscriptions
          .subscribe(initialSubscriptions)
          .timeout(subscriptionTimeout);
    }
  }

  Future<void> disconnect() async {
    await connection.disconnect();
  }

  Future<void> logout() async {
    await _authStorage.clearToken();
    await connection.disconnect();
  }

  String getAuthUrl(String provider, {String? redirectUri}) {
    final helper = OidcHelper(
      host: connection.host,
      database: connection.database,
      ssl: _ssl,
    );
    return helper.getAuthUrl(provider, redirectUri: redirectUri);
  }

  String? parseTokenFromCallback(String callbackUrl) {
    final helper = OidcHelper(
      host: connection.host,
      database: connection.database,
      ssl: _ssl,
    );
    return helper.parseTokenFromCallback(callbackUrl);
  }
}
