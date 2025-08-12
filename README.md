# Proxy Cloud

<p align="center">
  <img src="assets/images/logo.png" alt="Proxy Cloud Logo" width="150"/>
</p>

<p align="center">
  <img src="screenshots/base.jpg" alt="Proxy Cloud Screenshot" width="300"/>
</p>

<p align="center">
  <b>An open-source VPN that's fast, unlimited, secure, and completely free.</b>
</p>

## 🚀 Overview

Proxy Cloud is a modern, feature-rich Flutter application designed to provide secure, private internet access through V2Ray VPN technology and Telegram MTProto proxies. With an intuitive interface and powerful capabilities, Proxy Cloud puts you in control of your online privacy without any subscription fees or hidden costs.

## ✨ Key Features

### 🔒 V2Ray VPN
- **One-Tap Connection**: Connect to V2Ray servers instantly
- **Subscription Management**: Import and organize configurations via subscription URLs
- **Real-Time Monitoring**: Track connection status and performance
- **Custom VPN Settings**: Configure bypass subnets and DNS options

### 💬 Telegram Proxies
- **Extensive Proxy Collection**: Browse and connect to MTProto proxies worldwide
- **Detailed Information**: View country, provider, ping, and uptime statistics
- **Seamless Integration**: One-tap connection to Telegram via selected proxies
- **Easy Sharing**: Copy proxy details to clipboard for sharing

### 🛠️ Advanced Tools
- **IP Information**: View detailed information about your current IP address
- **Host Checker**: Test status, response time, and details of any web host
- **Speed Test**: Measure your internet connection performance
- **Subscription Store**: Discover and add new V2Ray configurations

### 🎨 Modern UI/UX
- **Sleek Design**: Dark theme with vibrant accents
- **Intuitive Navigation**: Easy access to all features
- **Smooth Animations**: Polished transitions and effects
- **Real-Time Indicators**: Visual feedback on connection status

## 📱 Installation

### Download

| Architecture | Download Link |
|-------------|---------------|
| Universal   | <a href="https://github.com/code3-dev/ProxyCloud/releases/latest/download/proxycloud-universal.apk"><img src="https://img.shields.io/badge/Android-Universal-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android Universal"></a> |
| armeabi-v7a | <a href="https://github.com/code3-dev/ProxyCloud/releases/latest/download/proxycloud-armeabi-v7a.apk"><img src="https://img.shields.io/badge/Android-armeabi--v7a-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android armeabi-v7a"></a> |
| arm64-v8a   | <a href="https://github.com/code3-dev/ProxyCloud/releases/latest/download/proxycloud-arm64-v8a.apk"><img src="https://img.shields.io/badge/Android-arm64--v8a-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android arm64-v8a"></a> |
| x86_64      | <a href="https://github.com/code3-dev/ProxyCloud/releases/latest/download/proxycloud-x86_64.apk"><img src="https://img.shields.io/badge/Android-x86_64-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android x86_64"></a> |

### For Developers

#### Prerequisites
- Flutter SDK (version ^3.7.2)
- Dart SDK
- Android Studio / VS Code
- Android device or emulator

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/code3-dev/ProxyCloud.git
   cd ProxyCloud
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Usage

### Setting up V2Ray
1. Navigate to the VPN tab
2. Tap on "Add License" to enter your subscription URL
3. Select a server from the list
4. Tap the connect button to establish a connection

### Using Telegram Proxies
1. Navigate to the Proxy tab
2. Browse the list of available proxies
3. Tap "Connect" on a proxy to open Telegram with the selected proxy
4. Alternatively, copy the proxy details to manually configure in Telegram

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Flutter](https://flutter.dev/) - UI toolkit for building natively compiled applications
- [flutter_v2ray](https://pub.dev/packages/flutter_v2ray) - Flutter plugin for V2Ray
- [Provider](https://pub.dev/packages/provider) - State management solution
- [url_launcher](https://pub.dev/packages/url_launcher) - URL launching capability
- [http](https://pub.dev/packages/http) - HTTP requests for API communication

## Contact

For questions, suggestions, or issues, please open an issue on the GitHub repository.