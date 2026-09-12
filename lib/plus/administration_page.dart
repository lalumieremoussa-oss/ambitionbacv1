import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdministrationPage extends StatefulWidget {
  const AdministrationPage({super.key});

  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://riyadh-9r3.pages.dev'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration en ligne'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }
}
