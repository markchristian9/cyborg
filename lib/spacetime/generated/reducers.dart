// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';
import 'package:spacetimedb_sdk/codegen.dart';
import 'reducer_args.dart';

class Reducers {
  Reducers(this._reducerCaller, this._reducerEmitter);

  final ReducerCaller _reducerCaller;

  final ReducerEmitter _reducerEmitter;

  /// Calls the `accept_hunt_lead` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> acceptHuntLead({
    required Int64 leadSeq,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(leadSeq);
    return await _reducerCaller.call(
      acceptHuntLeadDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `accept_invite` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> acceptInvite({
    required Int64 inviteId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(inviteId);
    return await _reducerCaller.call(
      acceptInviteDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `attack_monster` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> attackMonster({
    required Int64 monsterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(monsterId);
    return await _reducerCaller.call(
      attackMonsterDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `attack_player` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> attackPlayer({
    required Int64 targetCharacterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(targetCharacterId);
    return await _reducerCaller.call(
      attackPlayerDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `cast_skill` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> castSkill({
    required String skillId,
    required Int64 monsterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(skillId);
    encoder.writeU64(monsterId);
    return await _reducerCaller.call(
      castSkillDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `change_password` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> changePassword({
    required String currentPassword,
    required String newPassword,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(currentPassword);
    encoder.writeString(newPassword);
    return await _reducerCaller.call(
      changePasswordDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `create_character` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> createCharacter({
    required String name,
    required String kind,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(name);
    encoder.writeString(kind);
    return await _reducerCaller.call(
      createCharacterDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `create_party` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> createParty({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      createPartyDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `decline_invite` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> declineInvite({
    required Int64 inviteId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(inviteId);
    return await _reducerCaller.call(
      declineInviteDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `delete_character` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> deleteCharacter({
    required Int64 characterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(characterId);
    return await _reducerCaller.call(
      deleteCharacterDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `disband_party` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> disbandParty({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      disbandPartyDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `ensure_world_populated` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> ensureWorldPopulated({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      ensureWorldPopulatedDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `enter_world` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> enterWorld({
    required double gridX,
    required double gridY,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    return await _reducerCaller.call(
      enterWorldDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `invite_nearby` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> inviteNearby({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      inviteNearbyDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `invite_to_party` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> inviteToParty({
    required Int64 targetCharacterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(targetCharacterId);
    return await _reducerCaller.call(
      inviteToPartyDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `kick_member` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> kickMember({
    required Int64 targetCharacterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(targetCharacterId);
    return await _reducerCaller.call(
      kickMemberDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `leave_party` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> leaveParty({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      leavePartyDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `leave_world` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> leaveWorld({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      leaveWorldDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `login` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> login({
    required String email,
    required String password,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(email);
    encoder.writeString(password);
    return await _reducerCaller.call(
      loginDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `logout` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> logout({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      logoutDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `move_to` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> moveTo({
    required double gridX,
    required double gridY,
    required double facingX,
    required double facingY,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    encoder.writeF32(facingX);
    encoder.writeF32(facingY);
    return await _reducerCaller.call(
      moveToDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `on_update` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> onUpdate({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      onUpdateDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `pick_loot` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> pickLoot({
    required Int64 lootId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(lootId);
    return await _reducerCaller.call(
      pickLootDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `promote_leader` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> promoteLeader({
    required Int64 targetCharacterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(targetCharacterId);
    return await _reducerCaller.call(
      promoteLeaderDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `rebuild_monsters` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> rebuildMonsters({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      rebuildMonstersDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `register_account` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> registerAccount({
    required String email,
    required String password,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(email);
    encoder.writeString(password);
    return await _reducerCaller.call(
      registerAccountDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `report_progress` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> reportProgress({
    required int totalXp,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU32(totalXp);
    return await _reducerCaller.call(
      reportProgressDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `reset_timers` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> resetTimers({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      resetTimersDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `select_character` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> selectCharacter({
    required Int64 characterId,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU64(characterId);
    return await _reducerCaller.call(
      selectCharacterDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `set_following` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> setFollowing({
    required bool following,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeBool(following);
    return await _reducerCaller.call(
      setFollowingDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `start_hunt_lead` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> startHuntLead({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      startHuntLeadDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `stop_hunt_lead` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> stopHuntLead({
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    return await _reducerCaller.call(
      stopHuntLeadDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  /// Calls the `teleport_to` reducer.
  ///
  /// Returns a [TransactionResult] on success. Throws
  /// [SpacetimeDbReducerException] if the reducer returns `Failed` or
  /// `InternalError`. The returned status is one of `Committed`,
  /// `Pending` (queued to offline storage), or `Dropped` (skipped via
  /// `dropIfOffline: true` while offline).
  Future<TransactionResult> teleportTo({
    required String destination,
    required double gridX,
    required double gridY,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeString(destination);
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    return await _reducerCaller.call(
      teleportToDef.name,
      encoder.toBytes(),
      optimisticChanges: optimisticChanges,
      dropIfOffline: dropIfOffline,
    );
  }

  StreamSubscription<void> onAcceptHuntLead(
    void Function(EventContext ctx, Int64 leadSeq) callback,
  ) {
    return _reducerEmitter.on(acceptHuntLeadDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! AcceptHuntLeadArgs) return;
      callback(ctx, args.leadSeq);
    });
  }

  StreamSubscription<void> onAcceptInvite(
    void Function(EventContext ctx, Int64 inviteId) callback,
  ) {
    return _reducerEmitter.on(acceptInviteDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! AcceptInviteArgs) return;
      callback(ctx, args.inviteId);
    });
  }

  StreamSubscription<void> onAttackMonster(
    void Function(EventContext ctx, Int64 monsterId) callback,
  ) {
    return _reducerEmitter.on(attackMonsterDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! AttackMonsterArgs) return;
      callback(ctx, args.monsterId);
    });
  }

  StreamSubscription<void> onAttackPlayer(
    void Function(EventContext ctx, Int64 targetCharacterId) callback,
  ) {
    return _reducerEmitter.on(attackPlayerDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! AttackPlayerArgs) return;
      callback(ctx, args.targetCharacterId);
    });
  }

  StreamSubscription<void> onCastSkill(
    void Function(EventContext ctx, String skillId, Int64 monsterId) callback,
  ) {
    return _reducerEmitter.on(castSkillDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! CastSkillArgs) return;
      callback(ctx, args.skillId, args.monsterId);
    });
  }

  StreamSubscription<void> onChangePassword(
    void Function(EventContext ctx, String currentPassword, String newPassword)
    callback,
  ) {
    return _reducerEmitter.on(changePasswordDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! ChangePasswordArgs) return;
      callback(ctx, args.currentPassword, args.newPassword);
    });
  }

  StreamSubscription<void> onCreateCharacter(
    void Function(EventContext ctx, String name, String kind) callback,
  ) {
    return _reducerEmitter.on(createCharacterDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! CreateCharacterArgs) return;
      callback(ctx, args.name, args.kind);
    });
  }

  StreamSubscription<void> onCreateParty(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(createPartyDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! CreatePartyArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onDeclineInvite(
    void Function(EventContext ctx, Int64 inviteId) callback,
  ) {
    return _reducerEmitter.on(declineInviteDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! DeclineInviteArgs) return;
      callback(ctx, args.inviteId);
    });
  }

  StreamSubscription<void> onDeleteCharacter(
    void Function(EventContext ctx, Int64 characterId) callback,
  ) {
    return _reducerEmitter.on(deleteCharacterDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! DeleteCharacterArgs) return;
      callback(ctx, args.characterId);
    });
  }

  StreamSubscription<void> onDisbandParty(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(disbandPartyDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! DisbandPartyArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onEnsureWorldPopulated(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(ensureWorldPopulatedDef).listen((
      EventContext ctx,
    ) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! EnsureWorldPopulatedArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onEnterWorld(
    void Function(EventContext ctx, double gridX, double gridY) callback,
  ) {
    return _reducerEmitter.on(enterWorldDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! EnterWorldArgs) return;
      callback(ctx, args.gridX, args.gridY);
    });
  }

  StreamSubscription<void> onInviteNearby(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(inviteNearbyDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! InviteNearbyArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onInviteToParty(
    void Function(EventContext ctx, Int64 targetCharacterId) callback,
  ) {
    return _reducerEmitter.on(inviteToPartyDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! InviteToPartyArgs) return;
      callback(ctx, args.targetCharacterId);
    });
  }

  StreamSubscription<void> onKickMember(
    void Function(EventContext ctx, Int64 targetCharacterId) callback,
  ) {
    return _reducerEmitter.on(kickMemberDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! KickMemberArgs) return;
      callback(ctx, args.targetCharacterId);
    });
  }

  StreamSubscription<void> onLeaveParty(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(leavePartyDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! LeavePartyArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onLeaveWorld(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(leaveWorldDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! LeaveWorldArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onLogin(
    void Function(EventContext ctx, String email, String password) callback,
  ) {
    return _reducerEmitter.on(loginDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! LoginArgs) return;
      callback(ctx, args.email, args.password);
    });
  }

  StreamSubscription<void> onLogout(void Function(EventContext ctx) callback) {
    return _reducerEmitter.on(logoutDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! LogoutArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onMoveTo(
    void Function(
      EventContext ctx,
      double gridX,
      double gridY,
      double facingX,
      double facingY,
    )
    callback,
  ) {
    return _reducerEmitter.on(moveToDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! MoveToArgs) return;
      callback(ctx, args.gridX, args.gridY, args.facingX, args.facingY);
    });
  }

  StreamSubscription<void> onOnUpdate(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(onUpdateDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! OnUpdateArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onPickLoot(
    void Function(EventContext ctx, Int64 lootId) callback,
  ) {
    return _reducerEmitter.on(pickLootDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! PickLootArgs) return;
      callback(ctx, args.lootId);
    });
  }

  StreamSubscription<void> onPromoteLeader(
    void Function(EventContext ctx, Int64 targetCharacterId) callback,
  ) {
    return _reducerEmitter.on(promoteLeaderDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! PromoteLeaderArgs) return;
      callback(ctx, args.targetCharacterId);
    });
  }

  StreamSubscription<void> onRebuildMonsters(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(rebuildMonstersDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! RebuildMonstersArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onRegisterAccount(
    void Function(EventContext ctx, String email, String password) callback,
  ) {
    return _reducerEmitter.on(registerAccountDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! RegisterAccountArgs) return;
      callback(ctx, args.email, args.password);
    });
  }

  StreamSubscription<void> onReportProgress(
    void Function(EventContext ctx, int totalXp) callback,
  ) {
    return _reducerEmitter.on(reportProgressDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! ReportProgressArgs) return;
      callback(ctx, args.totalXp);
    });
  }

  StreamSubscription<void> onResetTimers(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(resetTimersDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! ResetTimersArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onSelectCharacter(
    void Function(EventContext ctx, Int64 characterId) callback,
  ) {
    return _reducerEmitter.on(selectCharacterDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! SelectCharacterArgs) return;
      callback(ctx, args.characterId);
    });
  }

  StreamSubscription<void> onSetFollowing(
    void Function(EventContext ctx, bool following) callback,
  ) {
    return _reducerEmitter.on(setFollowingDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! SetFollowingArgs) return;
      callback(ctx, args.following);
    });
  }

  StreamSubscription<void> onStartHuntLead(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(startHuntLeadDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! StartHuntLeadArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onStopHuntLead(
    void Function(EventContext ctx) callback,
  ) {
    return _reducerEmitter.on(stopHuntLeadDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! StopHuntLeadArgs) return;
      callback(ctx);
    });
  }

  StreamSubscription<void> onTeleportTo(
    void Function(
      EventContext ctx,
      String destination,
      double gridX,
      double gridY,
    )
    callback,
  ) {
    return _reducerEmitter.on(teleportToDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! TeleportToArgs) return;
      callback(ctx, args.destination, args.gridX, args.gridY);
    });
  }
}
