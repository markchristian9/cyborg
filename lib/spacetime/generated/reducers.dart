// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';
import 'package:spacetimedb_sdk/codegen.dart';
import 'reducer_args.dart';

class Reducers {
  Reducers(this._reducerCaller, this._reducerEmitter);

  final ReducerCaller _reducerCaller;

  final ReducerEmitter _reducerEmitter;

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
    required int level,
    required Int64 xp,
    List<OptimisticChange>? optimisticChanges,
    bool dropIfOffline = false,
  }) async {
    final encoder = BsatnEncoder();
    encoder.writeU32(level);
    encoder.writeU64(xp);
    return await _reducerCaller.call(
      reportProgressDef.name,
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
    void Function(EventContext ctx, int level, Int64 xp) callback,
  ) {
    return _reducerEmitter.on(reportProgressDef).listen((EventContext ctx) {
      final event = ctx.event;
      if (event is! ReducerEvent) return;
      final args = event.reducerArgs;
      if (args is! ReportProgressArgs) return;
      callback(ctx, args.level, args.xp);
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
}
