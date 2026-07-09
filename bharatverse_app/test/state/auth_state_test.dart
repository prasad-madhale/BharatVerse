import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/state/auth_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeAuthResponse extends Fake implements AuthResponse {}

void main() {
  late MockGoTrueClient mockAuthClient;

  setUpAll(() {
    registerFallbackValue(FakeAuthResponse());
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
  });
}
