import 'package:flutter/material.dart';
import 'package:testapp/screens/login_screen.dart';

class WelcomeScreen3 extends StatefulWidget {
  const WelcomeScreen3({super.key});

  @override
  State<WelcomeScreen3> createState() => _WelcomeScreen3State();
}

class _WelcomeScreen3State extends State<WelcomeScreen3> {
  final ScrollController _scrollController = ScrollController();
  double _scrollPosition = 0;
  double _opacity = 0;
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollPosition);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollPosition() {
    setState(() {
      _scrollPosition = _scrollController.position.pixels;
      // Calculamos opacidad basada en el scroll (aparece después de 100px)
      _opacity = (_scrollPosition > 50)
    ? 1.0
    : (_scrollPosition / 50).clamp(0.0, 1.0);

    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEEF1),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                // Espacio para el texto fijo (opcional)
                
                
                Padding(
                  padding: const EdgeInsets.only(top: 28.0),
                  child: Image.asset(
                    'assets/images/welcome3_image.png',
                    width: null,
                    height: null,
                    fit: BoxFit.scaleDown,
                  ),
                ),
                SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height * 0.00,
                ),
              ],
            ),
          ),
          
          // Texto "Saltar" FIJO en esquina superior derecha
          Positioned(
            bottom: 10,
            right: 30,
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: const Duration(milliseconds: 800),
              child: FloatingActionButton(
                backgroundColor: Colors.blue,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 400),
                    pageBuilder: (_, __, ___) => LoginScreen(),
                    transitionsBuilder: (_, animation, __, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1.0, 0.0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutQuart,
                        )),
                        child: child,
                      );
                    },
                  ),
                );

                },
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}