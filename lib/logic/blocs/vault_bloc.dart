import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/vault_repository.dart';
import '../../src/rust/api/vault.dart' as ffi;

// Events
abstract class VaultEvent extends Equatable {
  const VaultEvent();
  @override
  List<Object?> get props => [];
}

class CheckVaultStatusEvent extends VaultEvent {}

class OpenVaultEvent extends VaultEvent {
  final String path;
  final String password;
  const OpenVaultEvent({required this.path, required this.password});
  @override
  List<Object?> get props => [path, password];
}

class CreateVaultEvent extends VaultEvent {
  final String directory;
  final String name;
  final String password;
  const CreateVaultEvent({
    required this.directory,
    required this.name,
    required this.password,
  });
  @override
  List<Object?> get props => [directory, name, password];
}

class LockVaultEvent extends VaultEvent {}

class CheckConflictEvent extends VaultEvent {}

class ChangePasswordEvent extends VaultEvent {
  final String newPassword;
  const ChangePasswordEvent(this.newPassword);
  @override
  List<Object?> get props => [newPassword];
}

// States
abstract class VaultState extends Equatable {
  const VaultState();
  @override
  List<Object?> get props => [];
}

class VaultInitial extends VaultState {}

class VaultLoading extends VaultState {
  final String message;
  const VaultLoading(this.message);
  @override
  List<Object?> get props => [message];
}

class VaultLocked extends VaultState {
  final List<String> recentVaults;
  final String defaultDirectory;
  final List<ffi.LocalVaultItem> localVaults;
  const VaultLocked({
    this.recentVaults = const [],
    this.defaultDirectory = '',
    this.localVaults = const [],
  });
  @override
  List<Object?> get props => [recentVaults, defaultDirectory, localVaults];
}

class VaultUnlocked extends VaultState {
  final ffi.VaultInfo info;
  final bool conflictDetected;
  const VaultUnlocked({
    required this.info,
    this.conflictDetected = false,
  });
  @override
  List<Object?> get props => [info, conflictDetected];
}

class VaultFailure extends VaultState {
  final String error;
  const VaultFailure(this.error);
  @override
  List<Object?> get props => [error];
}

// Bloc
class VaultBloc extends Bloc<VaultEvent, VaultState> {
  final VaultRepository _repository;

  VaultBloc(this._repository) : super(VaultInitial()) {
    on<CheckVaultStatusEvent>(_onCheckStatus);
    on<OpenVaultEvent>(_onOpenVault);
    on<CreateVaultEvent>(_onCreateVault);
    on<LockVaultEvent>(_onLockVault);
    on<CheckConflictEvent>(_onCheckConflict);
    on<ChangePasswordEvent>(_onChangePassword);
  }

  Future<void> _onCheckStatus(
    CheckVaultStatusEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      final status = await _repository.getStatus();
      if (status.isUnlocked) {
        emit(VaultUnlocked(info: status, conflictDetected: status.externalConflict));
      } else {
        await _emitLocked(emit);
      }
    } catch (e) {
      await _emitLocked(emit);
    }
  }

  Future<void> _emitLocked(Emitter<VaultState> emit) async {
    final recents = await _repository.getRecentVaults();
    final defaultDir = await _repository.getDefaultVaultDirectory();
    final localVaults = await _repository.listLocalVaults(defaultDir);
    emit(VaultLocked(
      recentVaults: recents,
      defaultDirectory: defaultDir,
      localVaults: localVaults,
    ));
  }

  Future<void> _onOpenVault(
    OpenVaultEvent event,
    Emitter<VaultState> emit,
  ) async {
    emit(const VaultLoading('Дешифрование мастер-ключа (Argon2id)...'));
    try {
      final info = await _repository.open(event.path, event.password);
      emit(VaultUnlocked(info: info, conflictDetected: info.externalConflict));
    } catch (e) {
      emit(VaultFailure(e.toString()));
      await _emitLocked(emit);
    }
  }

  Future<void> _onCreateVault(
    CreateVaultEvent event,
    Emitter<VaultState> emit,
  ) async {
    emit(const VaultLoading('Генерация криптографического контейнера...'));
    try {
      final info = await _repository.create(
        event.directory,
        event.name,
        event.password,
      );
      emit(VaultUnlocked(info: info));
    } catch (e) {
      emit(VaultFailure(e.toString()));
      await _emitLocked(emit);
    }
  }

  Future<void> _onLockVault(
    LockVaultEvent event,
    Emitter<VaultState> emit,
  ) async {
    emit(const VaultLoading('Затирание ключей в RAM (zeroize)...'));
    try {
      await _repository.lock();
    } catch (_) {}
    await _emitLocked(emit);
  }

  Future<void> _onCheckConflict(
    CheckConflictEvent event,
    Emitter<VaultState> emit,
  ) async {
    if (state is VaultUnlocked) {
      final current = state as VaultUnlocked;
      final conflict = await _repository.checkConflict();
      if (conflict != current.conflictDetected) {
        emit(VaultUnlocked(info: current.info, conflictDetected: conflict));
      }
    }
  }

  Future<void> _onChangePassword(
    ChangePasswordEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      await _repository.changePassword(event.newPassword);
      final status = await _repository.getStatus();
      emit(VaultUnlocked(info: status));
    } catch (e) {
      emit(VaultFailure(e.toString()));
    }
  }
}
