import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp();
  SystemChrome.setSystemUIOverlayStyle(_systemUiStyle);
  runApp(const FilmswipeApp());
}

const _stageColor = Color(0xFF16130F);
const _accentColor = Color(0xFFF4A124);
const _searchMoviesUrl =
    'https://europe-west1-filmswipe-c4c22.cloudfunctions.net/searchMovies';
const _discoverMoviesUrl =
    'https://europe-west1-filmswipe-c4c22.cloudfunctions.net/discoverMovies';
const _movieDetailsUrl =
    'https://europe-west1-filmswipe-c4c22.cloudfunctions.net/getMovieDetails';
const _loadSocialStateUrl =
    'https://europe-west1-filmswipe-c4c22.cloudfunctions.net/loadSocialState';
const _connectFriendUrl =
    'https://europe-west1-filmswipe-c4c22.cloudfunctions.net/connectFriend';
const _minFeatureRuntimeMinutes = 60;
const _maxProfilePhotoDataUrlLength = 900000;
const _shareChannel = MethodChannel('com.filmswipe.app/share');

const _systemUiStyle = SystemUiOverlayStyle(
  statusBarColor: _stageColor,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: _stageColor,
  systemNavigationBarIconBrightness: Brightness.light,
);

Future<void>? _googleSignInInitialization;

Future<void> _ensureGoogleSignInInitialized() {
  return _googleSignInInitialization ??= GoogleSignIn.instance.initialize();
}

class FilmswipeApp extends StatelessWidget {
  const FilmswipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Filmswipe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _stageColor,
      ),
      home: const FilmswipeHome(),
    );
  }
}

class FilmswipeHome extends StatefulWidget {
  const FilmswipeHome({super.key});

  @override
  State<FilmswipeHome> createState() => _FilmswipeHomeState();
}

class _FilmswipeHomeState extends State<FilmswipeHome> {
  late final WebViewController _controller;
  final _imagePicker = ImagePicker();
  StreamSubscription<User?>? _authSubscription;
  var _loadingProgress = 0;
  var _webViewReady = false;
  var _profilePhotoPicking = false;
  var _handlingSystemBack = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_stageColor)
      ..addJavaScriptChannel(
        'FilmswipeBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _loadingProgress = 100;
                _webViewReady = true;
              });
            }
            unawaited(_notifyCurrentAuthState());
          },
        ),
      )
      ..loadFlutterAsset('index.html');

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      final currentUser = await _currentFirebaseUser(user);
      if (currentUser != null) {
        await _syncUserSession(currentUser);
      }
      await _notifyAuthState(currentUser);
    });
  }

  Future<User?> _currentFirebaseUser([User? user]) async {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return null;
    }
    if (currentUser.isAnonymous) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (error) {
        debugPrint('Firebase anonymous sign-out failed: $error');
      }
      return null;
    }
    return currentUser;
  }

  Future<void> _notifyCurrentAuthState() async {
    final user = await _currentFirebaseUser();
    await _notifyAuthState(user);
  }

  Future<void> _syncUserSession(User user) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final serverTime = FieldValue.serverTimestamp();

        if (snapshot.exists) {
          transaction.update(userRef, {
            'lastSeenAt': serverTime,
            'isAnonymous': user.isAnonymous,
            'displayName': user.displayName,
            'email': user.email,
            'photoUrl': user.photoURL,
            'providerIds': user.providerData
                .map((provider) => provider.providerId)
                .toList(),
          });
        } else {
          transaction.set(userRef, {
            'createdAt': serverTime,
            'lastSeenAt': serverTime,
            'isAnonymous': user.isAnonymous,
            'displayName': user.displayName,
            'email': user.email,
            'photoUrl': user.photoURL,
            'providerIds': user.providerData
                .map((provider) => provider.providerId)
                .toList(),
            'platform': 'android',
          });
        }
      });
    } on FirebaseException catch (error) {
      debugPrint('Firebase user sync failed: ${error.code} ${error.message}');
    } catch (error) {
      debugPrint('Firebase user sync failed: $error');
    }
  }

  Future<void> _handleBridgeMessage(JavaScriptMessage message) async {
    String? requestId;

    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      requestId = decoded['id']?.toString();
      final type = decoded['type']?.toString();
      final payload = decoded['payload'];

      if (requestId == null || type == null) {
        return;
      }

      if (type == 'getAuthState') {
        final user = await _currentFirebaseUser();
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'user': _userPayload(user)},
        });
      } else if (type == 'signInWithGoogle') {
        final user = await _signInWithGoogle();
        if (user != null) {
          await _syncUserSession(user);
        }
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'user': _userPayload(user)},
        });
      } else if (type == 'signInWithApple') {
        final user = await _signInWithApple();
        if (user != null) {
          await _syncUserSession(user);
        }
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'user': _userPayload(user)},
        });
      } else if (type == 'signOut') {
        try {
          await _ensureGoogleSignInInitialized();
          await GoogleSignIn.instance.signOut();
        } catch (error) {
          debugPrint('Google sign-out skipped: $error');
        }
        await FirebaseAuth.instance.signOut();
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'user': null},
        });
      } else if (type == 'updateProfileName') {
        final user = await _updateProfileName(payload);
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'user': _userPayload(user)},
        });
      } else if (type == 'loadProfileData') {
        final profileData = await _loadProfileData();
        await _sendBridgeResponse(requestId, {'ok': true, 'data': profileData});
      } else if (type == 'pickProfilePhoto') {
        final profileData = await _pickAndSaveProfilePhoto();
        await _sendBridgeResponse(requestId, {'ok': true, 'data': profileData});
      } else if (type == 'searchMovies') {
        await _handleMovieRequest(
          requestId,
          payload,
          _searchMoviesUrl,
          'No se pudo buscar en TMDB.',
        );
      } else if (type == 'discoverMovies') {
        await _handleMovieRequest(
          requestId,
          payload,
          _discoverMoviesUrl,
          'No se pudo cargar la cartelera.',
        );
      } else if (type == 'getMovieDetails') {
        await _handleMovieRequest(
          requestId,
          payload,
          _movieDetailsUrl,
          'No se pudo cargar la ficha de la película.',
        );
      } else if (type == 'loadSocialState') {
        await _handleMovieRequest(
          requestId,
          payload,
          _loadSocialStateUrl,
          'No se pudo cargar Amigos.',
        );
      } else if (type == 'connectFriend') {
        await _handleMovieRequest(
          requestId,
          payload,
          _connectFriendUrl,
          'No se pudo conectar con ese código.',
        );
      } else if (type == 'shareTogetherCode') {
        final code = _inviteCodeFromPayload(payload);
        if (code == null) {
          await _sendBridgeResponse(requestId, {
            'ok': false,
            'error': 'El código de invitación no es válido.',
          });
          return;
        }
        await _shareChannel.invokeMethod<void>('shareText', {
          'title': 'Invitación a Filmswipe',
          'text':
              'Únete a mí en Filmswipe para encontrar películas que ver juntos. Mi código es $code.',
        });
        await _sendBridgeResponse(requestId, {'ok': true, 'data': {}});
      } else if (type == 'loadMovieState') {
        final decisions = await _loadMovieDecisions();
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'decisions': decisions},
        });
      } else if (type == 'loadMovieComparisons') {
        final comparisons = await _loadMovieComparisons();
        await _sendBridgeResponse(requestId, {
          'ok': true,
          'data': {'comparisons': comparisons},
        });
      } else if (type == 'saveMovieDecision') {
        await _saveMovieDecision(payload);
        await _sendBridgeResponse(requestId, {'ok': true, 'data': {}});
      } else if (type == 'saveMovieComparison') {
        await _saveMovieComparison(payload);
        await _sendBridgeResponse(requestId, {'ok': true, 'data': {}});
      } else if (type == 'deleteMovieDecision') {
        await _deleteMovieDecision(payload);
        await _sendBridgeResponse(requestId, {'ok': true, 'data': {}});
      } else {
        await _sendBridgeResponse(requestId, {
          'ok': false,
          'error': 'Unknown native bridge request: $type',
        });
      }
    } on GoogleSignInException catch (error) {
      if (requestId != null) {
        await _sendBridgeResponse(requestId, {
          'ok': false,
          'error': _googleSignInMessage(error),
        });
      }
    } on FirebaseAuthException catch (error) {
      if (requestId != null) {
        debugPrint('Firebase auth failed: ${error.code} ${error.message}');
        await _sendBridgeResponse(requestId, {
          'ok': false,
          'error': _firebaseAuthMessage(error),
        });
      }
    } catch (error) {
      if (requestId != null) {
        await _sendBridgeResponse(requestId, {
          'ok': false,
          'error': error.toString(),
        });
      }
    }
  }

  String? _inviteCodeFromPayload(Object? payload) {
    if (payload is! Map) {
      return null;
    }
    final code = payload['code']?.toString().trim().toUpperCase() ?? '';
    return RegExp(r'^CINE\d{4}$').hasMatch(code) ? code : null;
  }

  Future<void> _handleMovieRequest(
    String requestId,
    Object? payload,
    String url,
    String fallbackError,
  ) async {
    final user = await _currentFirebaseUser();
    if (user == null) {
      await _sendBridgeResponse(requestId, {
        'ok': false,
        'error': 'No se ha podido iniciar sesión en Firebase.',
      });
      return;
    }

    final data = payload is Map<String, dynamic>
        ? payload
        : <String, dynamic>{};
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      await _sendBridgeResponse(requestId, {
        'ok': false,
        'error': 'No se ha podido validar la sesión.',
      });
      return;
    }

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'data': _jsonSafe(data)}),
    );
    final decoded = jsonDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorMessage = decoded is Map<String, dynamic>
          ? decoded['error'] is Map<String, dynamic>
                ? decoded['error']['message']?.toString()
                : decoded['error']?.toString()
          : null;
      await _sendBridgeResponse(requestId, {
        'ok': false,
        'error': errorMessage ?? fallbackError,
      });
      return;
    }

    final result = decoded is Map<String, dynamic>
        ? decoded['result']
        : <String, dynamic>{};

    await _sendBridgeResponse(requestId, {'ok': true, 'data': result});
  }

  Future<List<Map<String, dynamic>>> _loadMovieDecisions() async {
    final user = await _currentFirebaseUser();
    if (user == null) {
      return [];
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('movieDecisions')
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();
      final movie = data['movie'];
      final safeMovie = movie is Map ? _jsonSafe(movie) : null;
      return {
        'tmdbId': data['tmdbId'],
        'status': data['status'],
        if (safeMovie is Map && _isAllowedMoviePayload(safeMovie))
          'movie': safeMovie,
      };
    }).toList();
  }

  Future<User> _updateProfileName(Object? payload) async {
    final rawName = payload is Map<String, dynamic>
        ? payload['displayName']?.toString() ?? ''
        : '';
    final displayName = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (displayName.length < 2) {
      throw FirebaseAuthException(
        code: 'invalid-display-name',
        message: 'Escribe al menos 2 caracteres.',
      );
    }
    if (displayName.length > 40) {
      throw FirebaseAuthException(
        code: 'invalid-display-name',
        message: 'Usa 40 caracteres o menos.',
      );
    }

    final user = await _currentFirebaseUser();
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No se ha podido validar la sesión.',
      );
    }

    await user.updateDisplayName(displayName);
    await user.reload();

    final updatedUser = FirebaseAuth.instance.currentUser ?? user;
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(updatedUser.uid);
    final snapshot = await userRef.get();
    final serverTime = FieldValue.serverTimestamp();
    final data = {
      'lastSeenAt': serverTime,
      'isAnonymous': updatedUser.isAnonymous,
      'displayName': displayName,
      'email': updatedUser.email,
      'photoUrl': updatedUser.photoURL,
      'providerIds': updatedUser.providerData
          .map((provider) => provider.providerId)
          .toList(),
      'platform': 'android',
    };

    if (snapshot.exists) {
      await userRef.update(data);
    } else {
      await userRef.set({...data, 'createdAt': serverTime});
    }

    return updatedUser;
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    final user = await _currentFirebaseUser();
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No se ha podido validar la sesión.',
      );
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snapshot.data();

    return {
      'uid': user.uid,
      'profilePhotoDataUrl': _safeProfilePhotoDataUrl(
        data?['profilePhotoDataUrl'],
      ),
    };
  }

  Future<Map<String, dynamic>> _pickAndSaveProfilePhoto() async {
    if (_profilePhotoPicking) {
      throw FirebaseAuthException(
        code: 'profile-photo-busy',
        message: 'Ya se está eligiendo una foto.',
      );
    }

    _profilePhotoPicking = true;
    try {
      final user = await _currentFirebaseUser();
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-current-user',
          message: 'No se ha podido validar la sesión.',
        );
      }

      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
        requestFullMetadata: false,
      );

      if (image == null) {
        return {'uid': user.uid, 'cancelled': true};
      }

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        throw FirebaseAuthException(
          code: 'empty-profile-photo',
          message: 'No se ha podido leer esa foto.',
        );
      }

      final mimeType = _profilePhotoMimeType(image, bytes);
      final photoDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (photoDataUrl.length > _maxProfilePhotoDataUrlLength) {
        throw FirebaseAuthException(
          code: 'profile-photo-too-large',
          message: 'La foto pesa demasiado. Prueba con otra imagen.',
        );
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      await userRef.set({
        'profilePhotoDataUrl': photoDataUrl,
        'profilePhotoUpdatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
        'isAnonymous': user.isAnonymous,
        'displayName': user.displayName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'providerIds': user.providerData
            .map((provider) => provider.providerId)
            .toList(),
        'platform': 'android',
      }, SetOptions(merge: true));

      return {'uid': user.uid, 'profilePhotoDataUrl': photoDataUrl};
    } finally {
      _profilePhotoPicking = false;
    }
  }

  String? _safeProfilePhotoDataUrl(Object? value) {
    final dataUrl = value?.toString().trim() ?? '';
    if (dataUrl.isEmpty || dataUrl.length > _maxProfilePhotoDataUrlLength) {
      return null;
    }
    final pattern = RegExp(
      r'^data:image/(jpe?g|png|webp);base64,[A-Za-z0-9+/=]+$',
    );
    return pattern.hasMatch(dataUrl) ? dataUrl : null;
  }

  String _profilePhotoMimeType(XFile image, Uint8List bytes) {
    final mimeType = image.mimeType?.toLowerCase();
    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return mimeType!;
    }

    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  Future<void> _saveMovieDecision(Object? payload) async {
    final user = await _currentFirebaseUser();
    if (user == null || payload is! Map<String, dynamic>) {
      return;
    }

    final tmdbId = int.tryParse(payload['tmdbId']?.toString() ?? '');
    final status = payload['status']?.toString();
    const allowedStatuses = {'seen', 'watchlist', 'skipped'};

    if (tmdbId == null || status == null || !allowedStatuses.contains(status)) {
      return;
    }

    final movie = _jsonSafe(payload['movie']);
    if (movie is! Map || !_isAllowedMoviePayload(movie)) {
      return;
    }
    final document = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('movieDecisions')
        .doc(tmdbId.toString());

    await document.set({
      'tmdbId': tmdbId,
      'status': status,
      'movie': movie,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _deleteMovieDecision(Object? payload) async {
    final user = await _currentFirebaseUser();
    if (user == null || payload is! Map<String, dynamic>) {
      return;
    }

    final tmdbId = int.tryParse(payload['tmdbId']?.toString() ?? '');
    if (tmdbId == null) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('movieDecisions')
        .doc(tmdbId.toString())
        .delete();
  }

  Future<List<Map<String, dynamic>>> _loadMovieComparisons() async {
    final user = await _currentFirebaseUser();
    if (user == null) {
      return [];
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('movieComparisons')
        .get();
    final comparisons = <Map<String, dynamic>>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      final leftTmdbId = int.tryParse(data['leftTmdbId']?.toString() ?? '');
      final rightTmdbId = int.tryParse(data['rightTmdbId']?.toString() ?? '');
      final winnerTmdbId = int.tryParse(data['winnerTmdbId']?.toString() ?? '');
      if (leftTmdbId == null ||
          rightTmdbId == null ||
          winnerTmdbId == null ||
          leftTmdbId == rightTmdbId ||
          (winnerTmdbId != leftTmdbId && winnerTmdbId != rightTmdbId)) {
        continue;
      }
      comparisons.add({
        'leftTmdbId': leftTmdbId,
        'rightTmdbId': rightTmdbId,
        'winnerTmdbId': winnerTmdbId,
        'scope': data['scope']?.toString() == 'watchlist' ? 'watchlist' : 'seen',
      });
    }
    return comparisons;
  }

  Future<void> _saveMovieComparison(Object? payload) async {
    final user = await _currentFirebaseUser();
    if (user == null || payload is! Map<String, dynamic>) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No se ha podido validar la sesión.',
      );
    }

    final leftTmdbId = int.tryParse(payload['leftTmdbId']?.toString() ?? '');
    final rightTmdbId = int.tryParse(payload['rightTmdbId']?.toString() ?? '');
    final winnerTmdbId = int.tryParse(payload['winnerTmdbId']?.toString() ?? '');
    final scope = payload['scope']?.toString() == 'watchlist'
        ? 'watchlist'
        : 'seen';
    final requiredStatus = scope == 'watchlist' ? 'watchlist' : 'seen';
    if (leftTmdbId == null ||
        rightTmdbId == null ||
        winnerTmdbId == null ||
        leftTmdbId == rightTmdbId ||
        (winnerTmdbId != leftTmdbId && winnerTmdbId != rightTmdbId)) {
      throw ArgumentError('Comparación de películas no válida.');
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final decisions = await Future.wait([
      userRef.collection('movieDecisions').doc(leftTmdbId.toString()).get(),
      userRef.collection('movieDecisions').doc(rightTmdbId.toString()).get(),
    ]);
    if (decisions.any((document) => document.data()?['status'] != requiredStatus)) {
      throw StateError(
        scope == 'watchlist'
            ? 'Solo puedes ordenar películas pendientes.'
            : 'Solo puedes comparar películas vistas.',
      );
    }

    final firstId = leftTmdbId < rightTmdbId ? leftTmdbId : rightTmdbId;
    final secondId = leftTmdbId < rightTmdbId ? rightTmdbId : leftTmdbId;
    await userRef.collection('movieComparisons').doc('${scope}_${firstId}_$secondId').set({
      'leftTmdbId': leftTmdbId,
      'rightTmdbId': rightTmdbId,
      'winnerTmdbId': winnerTmdbId,
      'scope': scope,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    return value.toString();
  }

  bool _isAllowedMoviePayload(Map movie) {
    return _hasMovieCover(movie) &&
        _hasMovieReleaseDate(movie) &&
        _hasMovieRuntime(movie) &&
        !_isNonFeatureMoviePayload(movie) &&
        !_isPornographicMoviePayload(movie);
  }

  bool _hasMovieCover(Map movie) {
    final posterUrl = movie['posterUrl']?.toString().trim() ?? '';
    final posterPath = movie['posterPath']?.toString().trim() ?? '';
    return posterUrl.isNotEmpty || posterPath.isNotEmpty;
  }

  bool _hasMovieReleaseDate(Map movie) {
    final releaseDate = movie['releaseDate']?.toString().trim() ?? '';
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(releaseDate);
  }

  bool _hasMovieRuntime(Map movie) {
    final runtime = num.tryParse(movie['runtime']?.toString() ?? '');
    return runtime != null && runtime >= _minFeatureRuntimeMinutes;
  }

  String _movieKeywordText(Map movie) {
    final keywords = movie['keywords'];
    return keywords is Iterable
        ? keywords
              .map(
                (item) => item is Map
                    ? item['name']?.toString() ??
                          item['title']?.toString() ??
                          ''
                    : item.toString(),
              )
              .join(' ')
        : '';
  }

  bool _isNonFeatureMoviePayload(Map movie) {
    final runtime = num.tryParse(movie['runtime']?.toString() ?? '');
    if (runtime != null && runtime > 0 && runtime < _minFeatureRuntimeMinutes) {
      return true;
    }

    if (RegExp(
      r'\b(short film|short movie|short subject|cortometraje|stand-up comedy|stand up comedy|standup comedy|stand-up|stand up|standup|comedy special|tv special|television special|special episode|making of|behind the scenes|talk show|variety show|one-man show|one man show|live performance|stage performance|concert film|concert movie)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(_movieKeywordText(movie))) {
      return true;
    }

    final text = [
      movie['title'],
      movie['originalTitle'],
      movie['original_title'],
      movie['overview'],
      movie['synopsis'],
    ].whereType<Object>().join(' ');
    return RegExp(
      r'\b(short film|short movie|short subject|cortometraje|stand-up comedy|stand up comedy|standup comedy|stand-up special|stand up special|standup special|comedy special|tv special|television special|special episode|making of|behind the scenes|talk show|variety show|one-man show|one man show)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  bool _isPornographicMoviePayload(Map movie) {
    if (movie['adult'] == true) {
      return true;
    }

    if (RegExp(
      r'\b(adult film|adult movie|porn|porno|pornograf[ií]a|pornogr[aá]fic[oa]|hardcore|hard core|x-rated|x rated|xxx|softcore|soft core|sex film|sexploitation)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(_movieKeywordText(movie))) {
      return true;
    }

    final text = [
      movie['title'],
      movie['originalTitle'],
      movie['original_title'],
      movie['overview'],
      movie['synopsis'],
    ].whereType<Object>().join(' ');
    return RegExp(
      r'\b(adult film|adult movie|porn|porno|pornograf[ií]a|pornogr[aá]fic[oa]|hardcore|hard core|x-rated|x rated|xxx)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  Future<User?> _signInWithGoogle() async {
    await _ensureGoogleSignInInitialized();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
        description: 'Google Sign-In is not available on this device.',
      );
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
        description: 'Google did not return an ID token.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );
    return userCredential.user;
  }

  Future<User?> _signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCredential = await FirebaseAuth.instance.signInWithProvider(
      provider,
    );
    return userCredential.user;
  }

  String _googleSignInMessage(GoogleSignInException error) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return 'Inicio de sesión cancelado. Si no lo has cancelado tú, actualiza la app e inténtalo otra vez.';
    }
    return error.description ?? 'No se ha podido iniciar sesión con Google.';
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    final message = error.message;
    final normalizedMessage = message?.toLowerCase() ?? '';

    if (normalizedMessage.contains('package certificate hash')) {
      return 'No se ha podido validar la firma de esta instalación. Actualiza la app e inténtalo otra vez.';
    }
    if (error.code == 'web-context-canceled' ||
        error.code == 'canceled' ||
        normalizedMessage.contains('cancel')) {
      return 'Inicio de sesión cancelado.';
    }

    return message ?? 'No se ha podido iniciar sesión.';
  }

  Map<String, dynamic>? _userPayload(User? user) {
    if (user == null) {
      return null;
    }

    return {
      'uid': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'isAnonymous': user.isAnonymous,
      'providerIds': user.providerData
          .map((provider) => provider.providerId)
          .toList(),
    };
  }

  Future<void> _sendBridgeResponse(
    String requestId,
    Map<String, dynamic> response,
  ) async {
    final script =
        'window.__filmswipeNativeResolve(${jsonEncode(requestId)}, '
        '${jsonEncode(response)});';
    await _controller.runJavaScript(script);
  }

  Future<void> _notifyAuthState(User? user) async {
    if (!_webViewReady) {
      return;
    }

    final event = jsonEncode({
      'type': 'authState',
      'payload': {'user': _userPayload(user)},
    });
    try {
      await _controller.runJavaScript(
        'if (window.__filmswipeNativeEvent) '
        'window.__filmswipeNativeEvent($event);',
      );
    } catch (error) {
      debugPrint('Auth state bridge notification failed: $error');
    }
  }

  Future<bool> _handleWebViewBack() async {
    if (!_webViewReady) {
      return false;
    }

    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          if (typeof window.__filmswipeHandleNativeBack === 'function') {
            return window.__filmswipeHandleNativeBack();
          }
          return false;
        })();
      ''');
      final normalizedResult = result.toString().toLowerCase();
      return result == true ||
          normalizedResult == 'true' ||
          normalizedResult == '"true"';
    } catch (error) {
      debugPrint('Native back bridge failed: $error');
      return false;
    }
  }

  Future<void> _handleSystemBack() async {
    if (_handlingSystemBack) {
      return;
    }

    _handlingSystemBack = true;
    try {
      if (await _handleWebViewBack()) {
        return;
      }
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
      await SystemNavigator.pop();
    } finally {
      _handlingSystemBack = false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemUiStyle,
        child: Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loadingProgress < 100)
                  LinearProgressIndicator(
                    value: _loadingProgress / 100,
                    minHeight: 2,
                    color: _accentColor,
                    backgroundColor: Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
