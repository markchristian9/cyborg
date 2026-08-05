// GENERATED REDUCER ARGUMENT CLASSES AND DECODERS - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class AcceptHuntLeadArgs {
  AcceptHuntLeadArgs({required this.leadSeq});

  final Int64 leadSeq;
}

class AcceptHuntLeadArgsDecoder
    implements ReducerArgDecoder<AcceptHuntLeadArgs> {
  const AcceptHuntLeadArgsDecoder();

  @override
  AcceptHuntLeadArgs decode(BsatnDecoder decoder) {
    final leadSeq = decoder.readU64();
    return AcceptHuntLeadArgs(leadSeq: leadSeq);
  }
}

class AcceptInviteArgs {
  AcceptInviteArgs({required this.inviteId});

  final Int64 inviteId;
}

class AcceptInviteArgsDecoder implements ReducerArgDecoder<AcceptInviteArgs> {
  const AcceptInviteArgsDecoder();

  @override
  AcceptInviteArgs decode(BsatnDecoder decoder) {
    final inviteId = decoder.readU64();
    return AcceptInviteArgs(inviteId: inviteId);
  }
}

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

class AttackPlayerArgs {
  AttackPlayerArgs({required this.targetCharacterId});

  final Int64 targetCharacterId;
}

class AttackPlayerArgsDecoder implements ReducerArgDecoder<AttackPlayerArgs> {
  const AttackPlayerArgsDecoder();

  @override
  AttackPlayerArgs decode(BsatnDecoder decoder) {
    final targetCharacterId = decoder.readU64();
    return AttackPlayerArgs(targetCharacterId: targetCharacterId);
  }
}

class CastSkillArgs {
  CastSkillArgs({required this.skillId, required this.monsterId});

  final String skillId;

  final Int64 monsterId;
}

class CastSkillArgsDecoder implements ReducerArgDecoder<CastSkillArgs> {
  const CastSkillArgsDecoder();

  @override
  CastSkillArgs decode(BsatnDecoder decoder) {
    final skillId = decoder.readString();
    final monsterId = decoder.readU64();
    return CastSkillArgs(skillId: skillId, monsterId: monsterId);
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

class CreatePartyArgs {
  CreatePartyArgs();
}

class CreatePartyArgsDecoder implements ReducerArgDecoder<CreatePartyArgs> {
  const CreatePartyArgsDecoder();

  @override
  CreatePartyArgs decode(BsatnDecoder decoder) {
    return CreatePartyArgs();
  }
}

class DeclineInviteArgs {
  DeclineInviteArgs({required this.inviteId});

  final Int64 inviteId;
}

class DeclineInviteArgsDecoder implements ReducerArgDecoder<DeclineInviteArgs> {
  const DeclineInviteArgsDecoder();

  @override
  DeclineInviteArgs decode(BsatnDecoder decoder) {
    final inviteId = decoder.readU64();
    return DeclineInviteArgs(inviteId: inviteId);
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

class DisbandPartyArgs {
  DisbandPartyArgs();
}

class DisbandPartyArgsDecoder implements ReducerArgDecoder<DisbandPartyArgs> {
  const DisbandPartyArgsDecoder();

  @override
  DisbandPartyArgs decode(BsatnDecoder decoder) {
    return DisbandPartyArgs();
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
  EnterWorldArgs({required this.gridX, required this.gridY});

  final double gridX;

  final double gridY;
}

class EnterWorldArgsDecoder implements ReducerArgDecoder<EnterWorldArgs> {
  const EnterWorldArgsDecoder();

  @override
  EnterWorldArgs decode(BsatnDecoder decoder) {
    final gridX = decoder.readF32();
    final gridY = decoder.readF32();
    return EnterWorldArgs(gridX: gridX, gridY: gridY);
  }
}

class InviteNearbyArgs {
  InviteNearbyArgs();
}

class InviteNearbyArgsDecoder implements ReducerArgDecoder<InviteNearbyArgs> {
  const InviteNearbyArgsDecoder();

  @override
  InviteNearbyArgs decode(BsatnDecoder decoder) {
    return InviteNearbyArgs();
  }
}

class InviteToPartyArgs {
  InviteToPartyArgs({required this.targetCharacterId});

  final Int64 targetCharacterId;
}

class InviteToPartyArgsDecoder implements ReducerArgDecoder<InviteToPartyArgs> {
  const InviteToPartyArgsDecoder();

  @override
  InviteToPartyArgs decode(BsatnDecoder decoder) {
    final targetCharacterId = decoder.readU64();
    return InviteToPartyArgs(targetCharacterId: targetCharacterId);
  }
}

class KickMemberArgs {
  KickMemberArgs({required this.targetCharacterId});

  final Int64 targetCharacterId;
}

class KickMemberArgsDecoder implements ReducerArgDecoder<KickMemberArgs> {
  const KickMemberArgsDecoder();

  @override
  KickMemberArgs decode(BsatnDecoder decoder) {
    final targetCharacterId = decoder.readU64();
    return KickMemberArgs(targetCharacterId: targetCharacterId);
  }
}

class LeavePartyArgs {
  LeavePartyArgs();
}

class LeavePartyArgsDecoder implements ReducerArgDecoder<LeavePartyArgs> {
  const LeavePartyArgsDecoder();

  @override
  LeavePartyArgs decode(BsatnDecoder decoder) {
    return LeavePartyArgs();
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
  MoveToArgs({
    required this.gridX,
    required this.gridY,
    required this.facingX,
    required this.facingY,
  });

  final double gridX;

  final double gridY;

  final double facingX;

  final double facingY;
}

class MoveToArgsDecoder implements ReducerArgDecoder<MoveToArgs> {
  const MoveToArgsDecoder();

  @override
  MoveToArgs decode(BsatnDecoder decoder) {
    final gridX = decoder.readF32();
    final gridY = decoder.readF32();
    final facingX = decoder.readF32();
    final facingY = decoder.readF32();
    return MoveToArgs(
      gridX: gridX,
      gridY: gridY,
      facingX: facingX,
      facingY: facingY,
    );
  }
}

class OnUpdateArgs {
  OnUpdateArgs();
}

class OnUpdateArgsDecoder implements ReducerArgDecoder<OnUpdateArgs> {
  const OnUpdateArgsDecoder();

  @override
  OnUpdateArgs decode(BsatnDecoder decoder) {
    return OnUpdateArgs();
  }
}

class PickLootArgs {
  PickLootArgs({required this.lootId});

  final Int64 lootId;
}

class PickLootArgsDecoder implements ReducerArgDecoder<PickLootArgs> {
  const PickLootArgsDecoder();

  @override
  PickLootArgs decode(BsatnDecoder decoder) {
    final lootId = decoder.readU64();
    return PickLootArgs(lootId: lootId);
  }
}

class PromoteLeaderArgs {
  PromoteLeaderArgs({required this.targetCharacterId});

  final Int64 targetCharacterId;
}

class PromoteLeaderArgsDecoder implements ReducerArgDecoder<PromoteLeaderArgs> {
  const PromoteLeaderArgsDecoder();

  @override
  PromoteLeaderArgs decode(BsatnDecoder decoder) {
    final targetCharacterId = decoder.readU64();
    return PromoteLeaderArgs(targetCharacterId: targetCharacterId);
  }
}

class RebuildMonstersArgs {
  RebuildMonstersArgs();
}

class RebuildMonstersArgsDecoder
    implements ReducerArgDecoder<RebuildMonstersArgs> {
  const RebuildMonstersArgsDecoder();

  @override
  RebuildMonstersArgs decode(BsatnDecoder decoder) {
    return RebuildMonstersArgs();
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

class ResetTimersArgs {
  ResetTimersArgs();
}

class ResetTimersArgsDecoder implements ReducerArgDecoder<ResetTimersArgs> {
  const ResetTimersArgsDecoder();

  @override
  ResetTimersArgs decode(BsatnDecoder decoder) {
    return ResetTimersArgs();
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

class SetFollowingArgs {
  SetFollowingArgs({required this.following});

  final bool following;
}

class SetFollowingArgsDecoder implements ReducerArgDecoder<SetFollowingArgs> {
  const SetFollowingArgsDecoder();

  @override
  SetFollowingArgs decode(BsatnDecoder decoder) {
    final following = decoder.readBool();
    return SetFollowingArgs(following: following);
  }
}

class StartHuntLeadArgs {
  StartHuntLeadArgs();
}

class StartHuntLeadArgsDecoder implements ReducerArgDecoder<StartHuntLeadArgs> {
  const StartHuntLeadArgsDecoder();

  @override
  StartHuntLeadArgs decode(BsatnDecoder decoder) {
    return StartHuntLeadArgs();
  }
}

class StopHuntLeadArgs {
  StopHuntLeadArgs();
}

class StopHuntLeadArgsDecoder implements ReducerArgDecoder<StopHuntLeadArgs> {
  const StopHuntLeadArgsDecoder();

  @override
  StopHuntLeadArgs decode(BsatnDecoder decoder) {
    return StopHuntLeadArgs();
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

const acceptHuntLeadDef = ReducerDef<AcceptHuntLeadArgs>(
  'accept_hunt_lead',
  AcceptHuntLeadArgsDecoder(),
);
const acceptInviteDef = ReducerDef<AcceptInviteArgs>(
  'accept_invite',
  AcceptInviteArgsDecoder(),
);
const attackMonsterDef = ReducerDef<AttackMonsterArgs>(
  'attack_monster',
  AttackMonsterArgsDecoder(),
);
const attackPlayerDef = ReducerDef<AttackPlayerArgs>(
  'attack_player',
  AttackPlayerArgsDecoder(),
);
const castSkillDef = ReducerDef<CastSkillArgs>(
  'cast_skill',
  CastSkillArgsDecoder(),
);
const changePasswordDef = ReducerDef<ChangePasswordArgs>(
  'change_password',
  ChangePasswordArgsDecoder(),
);
const createCharacterDef = ReducerDef<CreateCharacterArgs>(
  'create_character',
  CreateCharacterArgsDecoder(),
);
const createPartyDef = ReducerDef<CreatePartyArgs>(
  'create_party',
  CreatePartyArgsDecoder(),
);
const declineInviteDef = ReducerDef<DeclineInviteArgs>(
  'decline_invite',
  DeclineInviteArgsDecoder(),
);
const deleteCharacterDef = ReducerDef<DeleteCharacterArgs>(
  'delete_character',
  DeleteCharacterArgsDecoder(),
);
const disbandPartyDef = ReducerDef<DisbandPartyArgs>(
  'disband_party',
  DisbandPartyArgsDecoder(),
);
const ensureWorldPopulatedDef = ReducerDef<EnsureWorldPopulatedArgs>(
  'ensure_world_populated',
  EnsureWorldPopulatedArgsDecoder(),
);
const enterWorldDef = ReducerDef<EnterWorldArgs>(
  'enter_world',
  EnterWorldArgsDecoder(),
);
const inviteNearbyDef = ReducerDef<InviteNearbyArgs>(
  'invite_nearby',
  InviteNearbyArgsDecoder(),
);
const inviteToPartyDef = ReducerDef<InviteToPartyArgs>(
  'invite_to_party',
  InviteToPartyArgsDecoder(),
);
const kickMemberDef = ReducerDef<KickMemberArgs>(
  'kick_member',
  KickMemberArgsDecoder(),
);
const leavePartyDef = ReducerDef<LeavePartyArgs>(
  'leave_party',
  LeavePartyArgsDecoder(),
);
const leaveWorldDef = ReducerDef<LeaveWorldArgs>(
  'leave_world',
  LeaveWorldArgsDecoder(),
);
const loginDef = ReducerDef<LoginArgs>('login', LoginArgsDecoder());
const logoutDef = ReducerDef<LogoutArgs>('logout', LogoutArgsDecoder());
const moveToDef = ReducerDef<MoveToArgs>('move_to', MoveToArgsDecoder());
const onUpdateDef = ReducerDef<OnUpdateArgs>(
  'on_update',
  OnUpdateArgsDecoder(),
);
const pickLootDef = ReducerDef<PickLootArgs>(
  'pick_loot',
  PickLootArgsDecoder(),
);
const promoteLeaderDef = ReducerDef<PromoteLeaderArgs>(
  'promote_leader',
  PromoteLeaderArgsDecoder(),
);
const rebuildMonstersDef = ReducerDef<RebuildMonstersArgs>(
  'rebuild_monsters',
  RebuildMonstersArgsDecoder(),
);
const registerAccountDef = ReducerDef<RegisterAccountArgs>(
  'register_account',
  RegisterAccountArgsDecoder(),
);
const reportProgressDef = ReducerDef<ReportProgressArgs>(
  'report_progress',
  ReportProgressArgsDecoder(),
);
const resetTimersDef = ReducerDef<ResetTimersArgs>(
  'reset_timers',
  ResetTimersArgsDecoder(),
);
const selectCharacterDef = ReducerDef<SelectCharacterArgs>(
  'select_character',
  SelectCharacterArgsDecoder(),
);
const setFollowingDef = ReducerDef<SetFollowingArgs>(
  'set_following',
  SetFollowingArgsDecoder(),
);
const startHuntLeadDef = ReducerDef<StartHuntLeadArgs>(
  'start_hunt_lead',
  StartHuntLeadArgsDecoder(),
);
const stopHuntLeadDef = ReducerDef<StopHuntLeadArgs>(
  'stop_hunt_lead',
  StopHuntLeadArgsDecoder(),
);
const teleportToDef = ReducerDef<TeleportToArgs>(
  'teleport_to',
  TeleportToArgsDecoder(),
);
