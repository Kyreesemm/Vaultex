import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/vault_entry.dart';
import '../../data/repositories/vault_repository.dart';

// Events
abstract class EntriesEvent extends Equatable {
  const EntriesEvent();
  @override
  List<Object?> get props => [];
}

class LoadEntriesEvent extends EntriesEvent {
  final EntryCategory category;
  final String query;
  const LoadEntriesEvent({
    this.category = EntryCategory.all,
    this.query = '',
  });
  @override
  List<Object?> get props => [category, query];
}

class SaveAccountEvent extends EntriesEvent {
  final String? id;
  final String service;
  final String username;
  final String email;
  final String password;
  final String? phone;
  final String? twoFactorSecret;
  final String? url;
  final String? notes;

  const SaveAccountEvent({
    this.id,
    required this.service,
    required this.username,
    required this.email,
    required this.password,
    this.phone,
    this.twoFactorSecret,
    this.url,
    this.notes,
  });

  @override
  List<Object?> get props => [id, service, username, email, password, phone, twoFactorSecret, url, notes];
}

class SaveApiTokenEvent extends EntriesEvent {
  final String? id;
  final String name;
  final String token;
  final String? expiresAt;
  final List<String> tags;
  final String? notes;

  const SaveApiTokenEvent({
    this.id,
    required this.name,
    required this.token,
    this.expiresAt,
    required this.tags,
    this.notes,
  });

  @override
  List<Object?> get props => [id, name, token, expiresAt, tags, notes];
}

class SaveSecretRecoveryEvent extends EntriesEvent {
  final String? id;
  final String name;
  final String secretType;
  final String value;
  final String? notes;

  const SaveSecretRecoveryEvent({
    this.id,
    required this.name,
    required this.secretType,
    required this.value,
    this.notes,
  });

  @override
  List<Object?> get props => [id, name, secretType, value, notes];
}

class SaveNoteEvent extends EntriesEvent {
  final String? id;
  final String title;
  final String content;
  final List<String> tags;

  const SaveNoteEvent({
    this.id,
    required this.title,
    required this.content,
    required this.tags,
  });

  @override
  List<Object?> get props => [id, title, content, tags];
}

class DeleteEntryEvent extends EntriesEvent {
  final String id;
  const DeleteEntryEvent(this.id);
  @override
  List<Object?> get props => [id];
}

// States
abstract class EntriesState extends Equatable {
  const EntriesState();
  @override
  List<Object?> get props => [];
}

class EntriesInitial extends EntriesState {}

class EntriesLoading extends EntriesState {}

class EntriesLoaded extends EntriesState {
  final List<VaultEntry> entries;
  final EntryCategory selectedCategory;
  final String query;
  final int totalAccounts;
  final int totalTokens;
  final int totalSecrets;
  final int totalNotes;

  const EntriesLoaded({
    required this.entries,
    required this.selectedCategory,
    required this.query,
    required this.totalAccounts,
    required this.totalTokens,
    required this.totalSecrets,
    required this.totalNotes,
  });

  int get totalAll => totalAccounts + totalTokens + totalSecrets + totalNotes;

  @override
  List<Object?> get props => [
        entries,
        selectedCategory,
        query,
        totalAccounts,
        totalTokens,
        totalSecrets,
        totalNotes,
      ];
}

class EntriesFailure extends EntriesState {
  final String error;
  const EntriesFailure(this.error);
  @override
  List<Object?> get props => [error];
}

// Bloc
class EntriesBloc extends Bloc<EntriesEvent, EntriesState> {
  final VaultRepository _repository;

  EntriesBloc(this._repository) : super(EntriesInitial()) {
    on<LoadEntriesEvent>(_onLoadEntries);
    on<SaveAccountEvent>(_onSaveAccount);
    on<SaveApiTokenEvent>(_onSaveApiToken);
    on<SaveSecretRecoveryEvent>(_onSaveSecretRecovery);
    on<SaveNoteEvent>(_onSaveNote);
    on<DeleteEntryEvent>(_onDeleteEntry);
  }

  Future<void> _onLoadEntries(
    LoadEntriesEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      final allEntries = await _repository.getEntries();
      final totalAccounts = allEntries.where((e) => e.category == EntryCategory.account).length;
      final totalTokens = allEntries.where((e) => e.category == EntryCategory.token).length;
      final totalSecrets = allEntries.where((e) => e.category == EntryCategory.secret).length;
      final totalNotes = allEntries.where((e) => e.category == EntryCategory.note).length;

      final filtered = await _repository.getEntries(
        kindFilter: event.category == EntryCategory.all ? null : event.category.nameStr,
        query: event.query.isEmpty ? null : event.query,
      );

      emit(EntriesLoaded(
        entries: filtered,
        selectedCategory: event.category,
        query: event.query,
        totalAccounts: totalAccounts,
        totalTokens: totalTokens,
        totalSecrets: totalSecrets,
        totalNotes: totalNotes,
      ));
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  Future<void> _onSaveAccount(
    SaveAccountEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      await _repository.saveAccount(
        id: event.id,
        service: event.service,
        username: event.username,
        email: event.email,
        password: event.password,
        phone: event.phone,
        twoFactorSecret: event.twoFactorSecret,
        url: event.url,
        notes: event.notes,
      );
      _reloadCurrent(emit);
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  Future<void> _onSaveApiToken(
    SaveApiTokenEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      await _repository.saveApiToken(
        id: event.id,
        name: event.name,
        token: event.token,
        expiresAt: event.expiresAt,
        tags: event.tags,
        notes: event.notes,
      );
      _reloadCurrent(emit);
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  Future<void> _onSaveSecretRecovery(
    SaveSecretRecoveryEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      await _repository.saveSecretRecovery(
        id: event.id,
        name: event.name,
        secretType: event.secretType,
        value: event.value,
        notes: event.notes,
      );
      _reloadCurrent(emit);
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  Future<void> _onSaveNote(
    SaveNoteEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      await _repository.saveNote(
        id: event.id,
        title: event.title,
        content: event.content,
        tags: event.tags,
      );
      _reloadCurrent(emit);
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  Future<void> _onDeleteEntry(
    DeleteEntryEvent event,
    Emitter<EntriesState> emit,
  ) async {
    try {
      await _repository.deleteEntry(event.id);
      _reloadCurrent(emit);
    } catch (e) {
      emit(EntriesFailure(e.toString()));
    }
  }

  void _reloadCurrent(Emitter<EntriesState> emit) {
    if (state is EntriesLoaded) {
      final s = state as EntriesLoaded;
      add(LoadEntriesEvent(category: s.selectedCategory, query: s.query));
    } else {
      add(const LoadEntriesEvent());
    }
  }
}
