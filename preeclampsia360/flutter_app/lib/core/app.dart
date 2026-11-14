import 'package:flutter/material.dart';
import 'api_client.dart';
import 'theme.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/app_shell.dart';

class Preeclampsia360App extends StatefulWidget { const Preeclampsia360App({super.key}); @override State<Preeclampsia360App> createState()=>_Preeclampsia360AppState(); }
class _Preeclampsia360AppState extends State<Preeclampsia360App> {
  bool ready=false;
  @override void initState(){super.initState(); ApiClient.instance.restore().then((_){if(mounted)setState(()=>ready=true);});}
  @override Widget build(BuildContext context)=>MaterialApp(title:'Preeclampsia 360',debugShowCheckedModeBanner:false,theme:buildAppTheme(),home:!ready?const Scaffold(body:Center(child:CircularProgressIndicator())):ApiClient.instance.isAuthenticated?const AppShell():const LoginScreen());
}
