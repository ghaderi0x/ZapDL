import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'asset_selector.dart';
import 'release.dart';
import 'semver.dart';
import 'update_service.dart';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  installing,
  error,
}

class UpdateState extends Equatable {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.asset,
    this.progress,
    this.speed = 0,
    this.file,
    this.verified = false,
    this.errorCode,
    this.checkedAt,
    this.outcome,
    this.localNote,
  });

  final UpdatePhase phase;
  final ReleaseInfo? release;
  final ReleaseAsset? asset;

  /// 0..1 while downloading; null when the size is unknown.
  final double? progress;
  final double speed;
  final String? file;

  /// True when the downloaded file's SHA-256 matched the published one.
  final bool verified;
  final String? errorCode;
  final DateTime? checkedAt;
  final InstallOutcome? outcome;

  /// For local installs: 'older' | 'same' | 'newer' | 'unknown'.
  final String? localNote;

  UpdateState copyWith({
    UpdatePhase? phase,
    ReleaseInfo? release,
    ReleaseAsset? asset,
    double? progress,
    bool clearProgress = false,
    double? speed,
    String? file,
    bool? verified,
    String? errorCode,
    bool clearError = false,
    DateTime? checkedAt,
    InstallOutcome? outcome,
    String? localNote,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        release: release ?? this.release,
        asset: asset ?? this.asset,
        progress: clearProgress ? null : (progress ?? this.progress),
        speed: speed ?? this.speed,
        file: file ?? this.file,
        verified: verified ?? this.verified,
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
        checkedAt: checkedAt ?? this.checkedAt,
        outcome: outcome ?? this.outcome,
        localNote: localNote ?? this.localNote,
      );

  @override
  List<Object?> get props => [
        phase,
        release?.tag,
        asset?.name,
        progress,
        speed,
        file,
        verified,
        errorCode,
        checkedAt,
        outcome,
        localNote,
      ];
}

class UpdateCubit extends Cubit<UpdateState> {
  UpdateCubit(this.service) : super(UpdateState(checkedAt: service.lastChecked));

  final UpdateService service;

  /// Looks for a newer release. [skipped] is a version the user chose to
  /// ignore; automatic checks stay silent for it (a manual check still shows it).
  /// Returns the newer release (if any and not skipped), so the caller can
  /// notify the user.
  Future<ReleaseInfo?> check({
    bool includePrereleases = false,
    bool force = true,
    String? skipped,
    bool silent = false,
  }) async {
    if (state.phase == UpdatePhase.checking ||
        state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.installing) {
      return null;
    }
    if (!silent) emit(state.copyWith(phase: UpdatePhase.checking, clearError: true));
    try {
      final r = await service.check(includePrereleases: includePrereleases, force: force);
      final rel = r.release;
      if (r.newer && rel != null) {
        final hidden = silent && skipped != null && skipped == rel.version.toString();
        if (hidden) {
          emit(state.copyWith(phase: UpdatePhase.upToDate, checkedAt: r.checkedAt));
          return null;
        }
        emit(UpdateState(
          phase: UpdatePhase.available,
          release: rel,
          asset: service.assetFor(rel),
          checkedAt: r.checkedAt,
        ));
        return rel;
      }
      emit(UpdateState(phase: UpdatePhase.upToDate, release: rel, checkedAt: r.checkedAt));
    } on UpdateException catch (e) {
      // Silent (automatic) checks never nag about network problems.
      if (!silent) {
        emit(state.copyWith(phase: UpdatePhase.error, errorCode: e.code));
      }
    }
    return null;
  }

  Future<void> download() async {
    final rel = state.release;
    final asset = state.asset;
    if (rel == null || asset == null) {
      emit(state.copyWith(phase: UpdatePhase.error, errorCode: 'noAsset'));
      return;
    }
    emit(state.copyWith(phase: UpdatePhase.downloading, clearProgress: true, clearError: true));
    try {
      final r = await service.download(rel, asset, onProgress: (got, total, speed) {
        if (isClosed || state.phase != UpdatePhase.downloading) return;
        emit(state.copyWith(
          progress: total > 0 ? (got / total).clamp(0.0, 1.0) : null,
          clearProgress: total <= 0,
          speed: speed,
        ));
      });
      emit(state.copyWith(
        phase: UpdatePhase.ready,
        file: r.file.path,
        verified: r.verified,
        progress: 1,
      ));
    } on UpdateException catch (e) {
      emit(state.copyWith(phase: UpdatePhase.error, errorCode: e.code));
    }
  }

  void cancelDownload() {
    service.pauseDownload();
    if (state.phase == UpdatePhase.downloading) {
      emit(state.copyWith(phase: UpdatePhase.available, clearProgress: true));
    }
  }

  /// Installs the downloaded file. Returns the outcome so the caller can exit
  /// the app when the installer needs it gone.
  Future<InstallOutcome?> install() async {
    final path = state.file;
    if (path == null) return null;
    emit(state.copyWith(phase: UpdatePhase.installing, clearError: true));
    try {
      final o = await service.install(File(path));
      emit(state.copyWith(phase: UpdatePhase.ready, outcome: o));
      return o;
    } on UpdateException catch (e) {
      emit(state.copyWith(phase: UpdatePhase.error, errorCode: e.code));
      return null;
    }
  }

  /// Prepares an update file the user picked from disk ("local update").
  /// Reports whether its version (from the file name) is older/same/newer and
  /// whether an adjacent `.sha256` file matched. Nothing is installed until
  /// [install] is called.
  Future<void> useLocalFile(File file) async {
    if (!isInstallableFile(file.path, service.platform)) {
      emit(state.copyWith(phase: UpdatePhase.error, errorCode: 'unsupported'));
      return;
    }
    final check = await service.verifyLocalFile(file);
    if (check == false) {
      emit(state.copyWith(phase: UpdatePhase.error, errorCode: 'checksum'));
      return;
    }
    final v = versionFromFileName(file.uri.pathSegments.last);
    final note = v == null
        ? 'unknown'
        : (v > service.currentVersion ? 'newer' : (v < service.currentVersion ? 'older' : 'same'));
    emit(UpdateState(
      phase: UpdatePhase.ready,
      file: file.path,
      verified: check == true,
      localNote: note,
      checkedAt: state.checkedAt,
    ));
  }

  void dismiss() => emit(UpdateState(checkedAt: state.checkedAt));

  SemVer get current => service.currentVersion;

  @override
  Future<void> close() async {
    await service.dispose();
    return super.close();
  }
}
