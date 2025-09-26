class AppConfig {
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.78.238.98:3001', // Android emulator -> host
    // on device/same machine use your LAN IP, e.g. http://192.168.1.15:3001
  );
  static const authToken = 'demo_token_123';
}
