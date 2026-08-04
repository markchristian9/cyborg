// GENERATED REDUCER ARGUMENT CLASSES AND DECODERS - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

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
  ReportProgressArgs({required this.level, required this.xp});

  final int level;

  final Int64 xp;
}

class ReportProgressArgsDecoder
    implements ReducerArgDecoder<ReportProgressArgs> {
  const ReportProgressArgsDecoder();

  @override
  ReportProgressArgs decode(BsatnDecoder decoder) {
    final level = decoder.readU32();
    final xp = decoder.readU64();
    return ReportProgressArgs(level: level, xp: xp);
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
const loginDef = ReducerDef<LoginArgs>('login', LoginArgsDecoder());
const logoutDef = ReducerDef<LogoutArgs>('logout', LogoutArgsDecoder());
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
