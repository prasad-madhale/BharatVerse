import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/state/auth_state.dart';

import '../support/like_fixtures.dart' show testUser;

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeAuthResponse extends Fake implements AuthResponse {}

class FakeUserResponse extends Fake implements UserResponse {}

void main() {
  late MockGoTrueClient mockAuthClient;

  setUpAll(() {
    registerFallbackValue(FakeAuthResponse());
    registerFallbackValue(UserAttributes());
  });

  setUp(() {
    mockAuthClient = MockGoTrueClient();
    when(() => mockAuthClient.onAuthStateChange)
        .thenAnswer((_) => const Stream.empty());
  });

  group('AuthState', () {
    test('isAuthenticated is false when there is no current user', () {
      when(() => mockAuthClient.currentUser).thenReturn(null);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.isAuthenticated, isFalse);
      expect(authState.currentUser, isNull);
    });

    test('isAuthenticated is true when there is a current user', () {
      final user = User(
        id: 'user-123',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-08T00:00:00Z',
        email: 'test@example.com',
      );
      when(() => mockAuthClient.currentUser).thenReturn(user);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.isAuthenticated, isTrue);
      expect(authState.currentUser?.email, 'test@example.com');
    });

    test('register calls signUp with the given email and password', () async {
      when(() => mockAuthClient.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => FakeAuthResponse());
      final authState = AuthState(authClient: mockAuthClient);

      await authState.register('test@example.com', 's3cret-password');

      verify(() => mockAuthClient.signUp(
            email: 'test@example.com',
            password: 's3cret-password',
          )).called(1);
    });

    test('login calls signInWithPassword with the given email and password',
        () async {
      when(() => mockAuthClient.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => FakeAuthResponse());
      final authState = AuthState(authClient: mockAuthClient);

      await authState.login('test@example.com', 's3cret-password');

      verify(() => mockAuthClient.signInWithPassword(
            email: 'test@example.com',
            password: 's3cret-password',
          )).called(1);
    });

    test('logout calls signOut', () async {
      when(() => mockAuthClient.signOut()).thenAnswer((_) async {});
      final authState = AuthState(authClient: mockAuthClient);

      await authState.logout();

      verify(() => mockAuthClient.signOut()).called(1);
    });

    test('register propagates AuthException on failure', () async {
      when(() => mockAuthClient.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(const AuthException('User already registered'));
      final authState = AuthState(authClient: mockAuthClient);

      expect(
        () => authState.register('test@example.com', 's3cret-password'),
        throwsA(isA<AuthException>()),
      );
    });

    test('notifies listeners on auth state changes from the stream', () async {
      final controller = StreamController<gotrue.AuthState>.broadcast();
      addTearDown(controller.close);
      when(() => mockAuthClient.onAuthStateChange)
          .thenAnswer((_) => controller.stream);
      when(() => mockAuthClient.currentUser).thenReturn(null);

      final authState = AuthState(authClient: mockAuthClient);
      var notified = false;
      authState.addListener(() => notified = true);

      controller.add(const gotrue.AuthState(AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(Duration.zero);

      expect(notified, isTrue);
    });

    test('authToken is the current session token', () {
      final session = Session(
        accessToken: 'user-token',
        tokenType: 'bearer',
        user: testUser(),
      );
      when(() => mockAuthClient.currentSession).thenReturn(session);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.authToken, 'user-token');
    });

    test('authToken is null when there is no session', () {
      when(() => mockAuthClient.currentSession).thenReturn(null);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.authToken, isNull);
    });
  });

  group('describeAuthError', () {
    const unreachable =
        'Could not reach the server. Check your connection and try again.';
    const generic = 'Something went wrong. Please try again.';

    test('says so plainly when the server cannot be reached', () {
      final error = AuthRetryableFetchException(
        message: 'ClientException: Failed to fetch, '
            'uri=http://127.0.0.1:54321/auth/v1/token',
      );

      expect(describeAuthError(error), unreachable);
    });

    test('does not show a server error body', () {
      final error = AuthRetryableFetchException(
        message: '<html>Bad gateway</html>',
        statusCode: '502',
      );

      expect(describeAuthError(error), generic);
    });

    test('does not show what it could not decode', () {
      final error = AuthUnknownException(
        message: 'Failed to decode error response',
        originalError: const FormatException('bad json'),
      );

      expect(describeAuthError(error), generic);
    });

    test("keeps Supabase's own message when it refuses a request", () {
      expect(
        describeAuthError(const AuthApiException('Invalid login credentials',
            statusCode: '400')),
        'Invalid login credentials',
      );
      expect(
        describeAuthError(const AuthException('User already registered')),
        'User already registered',
      );
      expect(
        describeAuthError(AuthWeakPasswordException(
          message: 'Password should be at least 6 characters.',
          statusCode: '422',
          reasons: const ['length'],
        )),
        'Password should be at least 6 characters.',
      );
    });

    test('asks for a fresh sign-in when the session is gone', () {
      expect(describeAuthError(AuthSessionMissingException()),
          'Your session has ended. Please sign in again.');
    });

    test('gives anything else a generic message', () {
      expect(describeAuthError(StateError('boom')), generic);
    });
  });

  group('AuthState.sendPasswordReset', () {
    void stubReset(Future<void> Function() answer) =>
        when(() => mockAuthClient.resetPasswordForEmail(any(),
            redirectTo: any(named: 'redirectTo'))).thenAnswer((_) => answer());

    test('asks Supabase to email a link that returns to the app', () async {
      stubReset(() async {});
      final authState = AuthState(
          authClient: mockAuthClient, resetRedirectTo: 'https://app.example/');

      await authState.sendPasswordReset('test@example.com');

      verify(() => mockAuthClient.resetPasswordForEmail('test@example.com',
          redirectTo: 'https://app.example/')).called(1);
    });

    test('names no page to return to when it is not running on the web',
        () async {
      stubReset(() async {});
      final authState = AuthState(authClient: mockAuthClient);

      await authState.sendPasswordReset('test@example.com');

      verify(() => mockAuthClient.resetPasswordForEmail('test@example.com',
          redirectTo: null)).called(1);
    });

    test('propagates AuthException on failure', () async {
      stubReset(() => Future.error(const AuthException('Too many requests')));
      final authState = AuthState(authClient: mockAuthClient);

      expect(
        authState.sendPasswordReset('test@example.com'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthState password recovery', () {
    late StreamController<gotrue.AuthState> changes;

    setUp(() {
      changes = StreamController<gotrue.AuthState>.broadcast();
      addTearDown(changes.close);
      when(() => mockAuthClient.onAuthStateChange)
          .thenAnswer((_) => changes.stream);
    });

    Future<void> emit(AuthChangeEvent event) async {
      changes.add(gotrue.AuthState(event, null));
      await Future<void>.delayed(Duration.zero);
    }

    void stubUpdate(Future<UserResponse> Function() answer) =>
        when(() => mockAuthClient.updateUser(any()))
            .thenAnswer((_) => answer());

    test('is not recovering until a reset link is followed', () async {
      final authState = AuthState(authClient: mockAuthClient);

      await emit(AuthChangeEvent.signedIn);

      expect(authState.isRecovering, isFalse);
    });

    test('is recovering, and tells listeners, once a reset link is followed',
        () async {
      final authState = AuthState(authClient: mockAuthClient);
      var notified = 0;
      authState.addListener(() => notified++);

      await emit(AuthChangeEvent.passwordRecovery);

      expect(authState.isRecovering, isTrue);
      expect(notified, 1);
    });

    test('counts a recovery that happened before it started listening',
        () async {
      when(() => mockAuthClient.onAuthStateChange).thenAnswer((_) =>
          Stream.value(
              const gotrue.AuthState(AuthChangeEvent.passwordRecovery, null)));

      final authState = AuthState(authClient: mockAuthClient);
      await Future<void>.delayed(Duration.zero);

      expect(authState.isRecovering, isTrue);
    });

    test('stays recovering through other events', () async {
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);

      await emit(AuthChangeEvent.tokenRefreshed);
      await emit(AuthChangeEvent.userUpdated);
      await emit(AuthChangeEvent.signedIn);

      expect(authState.isRecovering, isTrue);
    });

    test('signing out ends it', () async {
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);

      await emit(AuthChangeEvent.signedOut);

      expect(authState.isRecovering, isFalse);
    });

    test('updatePassword saves the new password and ends it', () async {
      stubUpdate(() async => FakeUserResponse());
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);
      var notified = 0;
      authState.addListener(() => notified++);

      await authState.updatePassword('new-secret');

      final saved = verify(() => mockAuthClient.updateUser(captureAny()))
          .captured
          .single as UserAttributes;
      expect(saved.password, 'new-secret');
      expect(authState.isRecovering, isFalse);
      expect(notified, 1);
    });

    test('a refused password leaves it going', () async {
      stubUpdate(() => Future.error(const AuthException('Too weak')));
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);

      await expectLater(
          authState.updatePassword('x'), throwsA(isA<AuthException>()));

      expect(authState.isRecovering, isTrue);
    });

    test('does not let an error from the SDK go unhandled', () async {
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);

      changes.addError(
          const AuthException('Email link is invalid or has expired'));
      await Future<void>.delayed(Duration.zero);

      expect(authState.isRecovering, isTrue);
    });

    test('finishRecovery ends it without saving anything', () async {
      final authState = AuthState(authClient: mockAuthClient);
      await emit(AuthChangeEvent.passwordRecovery);
      var notified = 0;
      authState.addListener(() => notified++);

      authState.finishRecovery();

      expect(authState.isRecovering, isFalse);
      expect(notified, 1);
      verifyNever(() => mockAuthClient.updateUser(any()));
    });
  });
}
