// GENERATED REDUCER ARGUMENT CLASSES AND DECODERS - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class AttackMonsterArgs {
  AttackMonsterArgs({required this.monsterId});

  final Int64 monsterId;
}

class AttackMonsterArgsDecoder implements ReducerArgDecoder<AttackMonsterArgs> {
  const AttackMonsterArgsDecoder();

  @override
  AttackMonsterArgs decode(BsatnDecoder decoder) {
    final monsterId = decoder.readU64();
    return AttackMonsterArgs(monsterId: monsterId);
  }
}

class ChangePasswordArgs {
  ChangePasswordArgs({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;

  final String newPassword;
}

class ChangePasswordArgsDecoder
    implements ReducerArgDecoder<ChangePasswordArgs> {
  const ChangePasswordArgsDecoder();

  @override
  ChangePasswordArgs decode(BsatnDecoder decoder) {
    final currentPassword = decoder.readString();
    final newPassword = decoder.readString();
    return ChangePasswordArgs(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}

class CreateCharacterArgs {
  CreateCharacterArgs({required this.name, required this.kind});

  final String name;

  final String kind;
}

class CreateCharacterArgsDecoder
    implements ReducerArgDecoder<CreateCharacterArgs> {
  const CreateCharacterArgsDecoder();

  @override
  CreateCharacterArgs decode(BsatnDecoder decoder) {
    final name = decoder.readString();
    final kind = decoder.readString();
    return CreateCharacterArgs(name: name, kind: kind);
  }
}

class DeleteCharacterArgs {
  DeleteCharacterArgs({required this.characterId});

  final Int64 characterId;
}

class DeleteCharacterArgsDecoder
    implements ReducerArgDecoder<DeleteCharacterArgs> {
  const DeleteCharacterArgsDecoder();

  @override
  DeleteCharacterArgs decode(BsatnDecoder decoder) {
    final characterId = decoder.readU64();
    return DeleteCharacterArgs(characterId: characterId);
  }
}

class EnsureWorldPopulatedArgs {
  EnsureWorldPopulatedArgs();
}

class EnsureWorldPopulatedArgsDecoder
    implements ReducerArgDecoder<EnsureWorldPopulatedArgs> {
  const EnsureWorldPopulatedArgsDecoder();

  @override
  EnsureWorldPopulatedArgs decode(BsatnDecoder decoder) {
    return EnsureWorldPopulatedArgs();
  }
}

class EnterWorldArgs {
  EnterWorldArgs();
}

class EnterWorldArgsDecoder implements ReducerArgDecoder<EnterWorldArgs> {
  const EnterWorldArgsDecoder();

  @override
  EnterWorldArgs decode(BsatnDecoder decoder) {
    return EnterWorldArgs();
  }
}

class LeaveWorldArgs {
  LeaveWorldArgs();
}

class LeaveWorldArgsDecoder implements ReducerArgDecoder<LeaveWorldArgs> {
  const LeaveWorldArgsDecoder();

  @override
  LeaveWorldArgs decode(BsatnDecoder decoder) {
    return LeaveWorldArgs();
  }
}

class LoginArgs {
  LoginArgs({required this.email, required this.password});

  final String email;

  final String password;
}

class LoginArgsDecoder implements ReducerArgDecoder<LoginArgs> {
  const LoginArgsDecoder();

  @override
  LoginArgs decode(BsatnDecoder decoder) {
    final email = decoder.readString();
    final password = decoder.readString();
    return LoginArgs(email: email, password: password);
  }
}

class LogoutArgs {
  LogoutArgs();
}

class LogoutArgsDecoder implements ReducerArgDecoder<LogoutArgs> {
  const LogoutArgsDecoder();

  @override
  LogoutArgs decode(BsatnDecoder decoder) {
    return LogoutArgs();
  }
}

class MoveToArgs {
  MoveToArgs({required this.gridX, required this.gridY});

  final double gridX;

  final double gridY;
}

class MoveToArgsDecoder implements ReducerArgDecoder<MoveToArgs> {
  const MoveToArgsDecoder();

  @override
  MoveToArgs decode(BsatnDecoder decoder) {
    final gridX = decoder.readF32();
    final gridY = decoder.readF32();
    return MoveToArgs(gridX: gridX, gridY: gridY);
  }
}

class RegisterAccountArgs {
  RegisterAccountArgs({required this.email, required this.password});

  final String email;

  final String password;
}

class RegisterAccountArgsDecoder
    implements ReducerArgDecoder<RegisterAccountArgs> {
  const RegisterAccountArgsDecoder();

  @override
  RegisterAccountArgs decode(BsatnDecoder decoder) {
    final email = decoder.readString();
    final password = decoder.readString();
    return RegisterAccountArgs(email: email, password: password);
  }
}

class ReportProgressArgs {
  ReportProgressArgs({required this.totalXp});

  final int totalXp;
}

class ReportProgressArgsDecoder
    implements ReducerArgDecoder<ReportProgressArgs> {
  const ReportProgressArgsDecoder();

  @override
  ReportProgressArgs decode(BsatnDecoder decoder) {
    final totalXp = decoder.readU32();
    return ReportProgressArgs(totalXp: totalXp);
  }
}

class SelectCharacterArgs {
  SelectCharacterArgs({required this.characterId});

  final Int64 characterId;
}

class SelectCharacterArgsDecoder
    implements ReducerArgDecoder<SelectCharacterArgs> {
  const SelectCharacterArgsDecoder();

  @override
  SelectCharacterArgs decode(BsatnDecoder decoder) {
    final characterId = decoder.readU64();
    return SelectCharacterArgs(characterId: characterId);
  }
}

class TeleportToArgs {
  TeleportToArgs({
    required this.destination,
    required this.gridX,
    required this.gridY,
  });

  final String destination;

  final double gridX;

  final double gridY;
}

class TeleportToArgsDecoder implements ReducerArgDecoder<TeleportToArgs> {
  const TeleportToArgsDecoder();

  @override
  TeleportToArgs decode(BsatnDecoder decoder) {
    final destination = decoder.readString();
    final gridX = decoder.readF32();
    final gridY = decoder.readF32();
    return TeleportToArgs(destination: destination, gridX: gridX, gridY: gridY);
  }
}

const attackMonsterDef = ReducerDef<AttackMonsterArgs>(
  'attack_monster',
  AttackMonsterArgsDecoder(),
);
const changePasswordDef = ReducerDef<ChangePasswordArgs>(
  'change_password',
  ChangePasswordArgsDecoder(),
);
const createCharacterDef = ReducerDef<CreateCharacterArgs>(
  'create_character',
  CreateCharacterArgsDecoder(),
);
const deleteCharacterDef = ReducerDef<DeleteCharacterArgs>(
  'delete_character',
  DeleteCharacterArgsDecoder(),
);
const ensureWorldPopulatedDef = ReducerDef<EnsureWorldPopulatedArgs>(
  'ensure_world_populated',
  EnsureWorldPopulatedArgsDecoder(),
);
const enterWorldDef = ReducerDef<EnterWorldArgs>(
  'enter_world',
  EnterWorldArgsDecoder(),
);
const leaveWorldDef = ReducerDef<LeaveWorldArgs>(
  'leave_world',
  LeaveWorldArgsDecoder(),
);
const loginDef = ReducerDef<LoginArgs>('login', LoginArgsDecoder());
const logoutDef = ReducerDef<LogoutArgs>('logout', LogoutArgsDecoder());
const moveToDef = ReducerDef<MoveToArgs>('move_to', MoveToArgsDecoder());
const registerAccountDef = ReducerDef<RegisterAccountArgs>(
  'register_account',
  RegisterAccountArgsDecoder(),
);
const reportProgressDef = ReducerDef<ReportProgressArgs>(
  'report_progress',
  ReportProgressArgsDecoder(),
);
const selectCharacterDef = ReducerDef<SelectCharacterArgs>(
  'select_character',
  SelectCharacterArgsDecoder(),
);
const teleportToDef = ReducerDef<TeleportToArgs>(
  'teleport_to',
  TeleportToArgsDecoder(),
);
