// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:spacetimedb_sdk/codegen.dart';
import 'reducers.dart';
import 'reducer_args.dart';
import 'monster_ai_timer.dart';
import 'account.dart';
import 'loot.dart';
import 'monster_kill.dart';
import 'account_secret.dart';
import 'world_player.dart';
import 'party_invite.dart';
import 'leaderboard_entry.dart';
import 'player_character.dart';
import 'party_member.dart';
import 'monster.dart';
import 'monster_tick_timer.dart';
import 'session.dart';
import 'regen_timer.dart';
import 'party.dart';

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

  TableCache<MonsterAiTimer> get monsterAiTimer {
    return subscriptions.cache.getTableByTypedName<MonsterAiTimer>(
      'monster_ai_timer',
    );
  }

  TableCache<Account> get account {
    return subscriptions.cache.getTableByTypedName<Account>('account');
  }

  TableCache<Loot> get loot {
    return subscriptions.cache.getTableByTypedName<Loot>('loot');
  }

  TableCache<MonsterKill> get monsterKill {
    return subscriptions.cache.getTableByTypedName<MonsterKill>('monster_kill');
  }

  TableCache<AccountSecret> get accountSecret {
    return subscriptions.cache.getTableByTypedName<AccountSecret>(
      'account_secret',
    );
  }

  TableCache<WorldPlayer> get worldPlayer {
    return subscriptions.cache.getTableByTypedName<WorldPlayer>('world_player');
  }

  TableCache<PartyInvite> get partyInvite {
    return subscriptions.cache.getTableByTypedName<PartyInvite>('party_invite');
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

  TableCache<PartyMember> get partyMember {
    return subscriptions.cache.getTableByTypedName<PartyMember>('party_member');
  }

  TableCache<Monster> get monster {
    return subscriptions.cache.getTableByTypedName<Monster>('monster');
  }

  TableCache<MonsterTickTimer> get monsterTickTimer {
    return subscriptions.cache.getTableByTypedName<MonsterTickTimer>(
      'monster_tick_timer',
    );
  }

  TableCache<Session> get session {
    return subscriptions.cache.getTableByTypedName<Session>('session');
  }

  TableCache<RegenTimer> get regenTimer {
    return subscriptions.cache.getTableByTypedName<RegenTimer>('regen_timer');
  }

  TableCache<Party> get party {
    return subscriptions.cache.getTableByTypedName<Party>('party');
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

  Party? get myParty {
    final cache = subscriptions.cache.getTableByTypedName<Party>('my_party');
    final iterator = cache.iter().iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  TableCache<PartyInvite> get myPartyInvites {
    return subscriptions.cache.getTableByTypedName<PartyInvite>(
      'my_party_invites',
    );
  }

  TableCache<PartyMember> get myPartyMembers {
    return subscriptions.cache.getTableByTypedName<PartyMember>(
      'my_party_members',
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

  WorldPlayer? get myWorldPlayer {
    final cache = subscriptions.cache.getTableByTypedName<WorldPlayer>(
      'my_world_player',
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

    subscriptionManager.cache.registerDecoder<MonsterAiTimer>(
      'monster_ai_timer',
      MonsterAiTimerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Account>(
      'account',
      AccountDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Loot>('loot', LootDecoder());
    subscriptionManager.cache.registerDecoder<MonsterKill>(
      'monster_kill',
      MonsterKillDecoder(),
    );
    subscriptionManager.cache.registerDecoder<AccountSecret>(
      'account_secret',
      AccountSecretDecoder(),
    );
    subscriptionManager.cache.registerDecoder<WorldPlayer>(
      'world_player',
      WorldPlayerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PartyInvite>(
      'party_invite',
      PartyInviteDecoder(),
    );
    subscriptionManager.cache.registerDecoder<LeaderboardEntry>(
      'leaderboard_entry',
      LeaderboardEntryDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PlayerCharacter>(
      'player_character',
      PlayerCharacterDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PartyMember>(
      'party_member',
      PartyMemberDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Monster>(
      'monster',
      MonsterDecoder(),
    );
    subscriptionManager.cache.registerDecoder<MonsterTickTimer>(
      'monster_tick_timer',
      MonsterTickTimerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Session>(
      'session',
      SessionDecoder(),
    );
    subscriptionManager.cache.registerDecoder<RegenTimer>(
      'regen_timer',
      RegenTimerDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Party>('party', PartyDecoder());

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
    subscriptionManager.cache.registerDecoder<Party>(
      'my_party',
      PartyDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PartyInvite>(
      'my_party_invites',
      PartyInviteDecoder(),
    );
    subscriptionManager.cache.registerDecoder<PartyMember>(
      'my_party_members',
      PartyMemberDecoder(),
    );
    subscriptionManager.cache.registerDecoder<LeaderboardEntry>(
      'my_rank',
      LeaderboardEntryDecoder(),
    );
    subscriptionManager.cache.registerDecoder<Session>(
      'my_session',
      SessionDecoder(),
    );
    subscriptionManager.cache.registerDecoder<WorldPlayer>(
      'my_world_player',
      WorldPlayerDecoder(),
    );

    subscriptionManager.reducerRegistry.register(acceptHuntLeadDef);
    subscriptionManager.reducerRegistry.register(acceptInviteDef);
    subscriptionManager.reducerRegistry.register(attackMonsterDef);
    subscriptionManager.reducerRegistry.register(attackPlayerDef);
    subscriptionManager.reducerRegistry.register(castSkillDef);
    subscriptionManager.reducerRegistry.register(changePasswordDef);
    subscriptionManager.reducerRegistry.register(createCharacterDef);
    subscriptionManager.reducerRegistry.register(createPartyDef);
    subscriptionManager.reducerRegistry.register(declineInviteDef);
    subscriptionManager.reducerRegistry.register(deleteCharacterDef);
    subscriptionManager.reducerRegistry.register(disbandPartyDef);
    subscriptionManager.reducerRegistry.register(ensureWorldPopulatedDef);
    subscriptionManager.reducerRegistry.register(enterWorldDef);
    subscriptionManager.reducerRegistry.register(inviteNearbyDef);
    subscriptionManager.reducerRegistry.register(inviteToPartyDef);
    subscriptionManager.reducerRegistry.register(kickMemberDef);
    subscriptionManager.reducerRegistry.register(leavePartyDef);
    subscriptionManager.reducerRegistry.register(leaveWorldDef);
    subscriptionManager.reducerRegistry.register(loginDef);
    subscriptionManager.reducerRegistry.register(logoutDef);
    subscriptionManager.reducerRegistry.register(moveToDef);
    subscriptionManager.reducerRegistry.register(onUpdateDef);
    subscriptionManager.reducerRegistry.register(pickLootDef);
    subscriptionManager.reducerRegistry.register(promoteLeaderDef);
    subscriptionManager.reducerRegistry.register(rebuildMonstersDef);
    subscriptionManager.reducerRegistry.register(registerAccountDef);
    subscriptionManager.reducerRegistry.register(reportProgressDef);
    subscriptionManager.reducerRegistry.register(resetTimersDef);
    subscriptionManager.reducerRegistry.register(selectCharacterDef);
    subscriptionManager.reducerRegistry.register(setFollowingDef);
    subscriptionManager.reducerRegistry.register(startHuntLeadDef);
    subscriptionManager.reducerRegistry.register(stopHuntLeadDef);
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
