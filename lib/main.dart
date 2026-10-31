import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/security_service.dart';
import 'core/theme.dart';
import 'data/repositories/vault_repository.dart';
import 'logic/blocs/entries_bloc.dart';
import 'logic/blocs/vault_bloc.dart';
import 'src/rust/frb_generated.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/vault_picker_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flutter_rust_bridge runtime
  await RustLib.init();

  runApp(const VaultexApp());
}

class VaultexApp extends StatefulWidget {
  const VaultexApp({super.key});

  @override
  State<VaultexApp> createState() => _VaultexAppState();
}

class _VaultexAppState extends State<VaultexApp> with WidgetsBindingObserver {
  final VaultRepository _repository = VaultRepository();
  late final VaultBloc _vaultBloc;
  late final EntriesBloc _entriesBloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _vaultBloc = VaultBloc(_repository);
    _entriesBloc = EntriesBloc(_repository);

    // Initial check
    _vaultBloc.add(CheckVaultStatusEvent());

    // Security auto-lock initialization
    SecurityService().init(() {
      // Callback when inactivity timer fires
      if (_vaultBloc.state is VaultUnlocked) {
        _vaultBloc.add(LockVaultEvent());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vaultBloc.close();
    _entriesBloc.close();
    super.dispose();
  }

  /// App Lifecycle Security Policy (Master Specification Section 4):
  /// When app goes to background / paused / detached, immediately lock the vault
  /// and zeroize plaintext/keys in memory.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_vaultBloc.state is VaultUnlocked) {
        _vaultBloc.add(LockVaultEvent());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<VaultBloc>.value(value: _vaultBloc),
        BlocProvider<EntriesBloc>.value(value: _entriesBloc),
      ],
      child: Listener(
        // Resets inactivity timer on any user tap or touch
        onPointerDown: (_) => SecurityService().resetInactivityTimer(),
        behavior: HitTestBehavior.translucent,
        child: MaterialApp(
          title: 'Vaultex',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark, // Default to dark modern aesthetic
          home: BlocListener<VaultBloc, VaultState>(
            listener: (context, state) {
              if (state is VaultUnlocked) {
                _entriesBloc.add(const LoadEntriesEvent());
                SecurityService().resetInactivityTimer();
              } else if (state is VaultLocked) {
                SecurityService().stopInactivityTimer();
              }
            },
            child: BlocBuilder<VaultBloc, VaultState>(
              builder: (context, state) {
                if (state is VaultUnlocked) {
                  return const HomeScreen();
                }
                return const VaultPickerScreen();
              },
            ),
          ),
        ),
      ),
    );
  }
}
