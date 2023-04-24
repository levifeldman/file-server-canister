import 'package:flutter/material.dart'; 
class Palette { 
  static const MaterialColor kToDark = const MaterialColor( 
    0xffb71c1c, // 0% comes in here, this will be color picked if no shade is selected when defining a Color property which doesn’t require a swatch. 
    const <int, Color>{ 
      50: const Color(0xffa51919 ),//10% 
      100: const Color(0xff921616),//20% 
      200: const Color(0xff801414),//30% 
      300: const Color(0xff6e1111),//40% 
      400: const Color(0xff5c0e0e),//50% 
      500: const Color(0xff490b0b),//60% 
      600: const Color(0xff370808),//70% 
      700: const Color(0xff250606),//80% 
      800: const Color(0xff120303),//90% 
      900: const Color(0xff000000),//100% 
    }, 
  ); 
} // you can define define int 500 as the default shade and add your lighter tints above and darker tints below. 

