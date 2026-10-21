// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.projectUrl,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } else {
    debugPrint(
      'Supabase is not initialized. Start the app with SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY.',
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor:  const Color.fromARGB(255, 26, 11, 42),

        body: Stack(
            children: [

              Positioned(top: -35,left: 250,
                child: Container(
                width: 250,
                height:250,
                decoration: BoxDecoration (
                  shape:BoxShape.circle,
                   color: Color.fromARGB(0, 0, 0, 0),
                   boxShadow: [BoxShadow(
                    blurRadius: 135, color: Color.fromARGB(226, 217, 8, 228),spreadRadius: 50)]),
              ),
        ),

                Positioned(top:680, left:-135,
              child: Container(
                width:300,
                height:300,
                decoration: BoxDecoration (
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    blurRadius: 135,color: Color.fromARGB(226, 12, 18, 182),spreadRadius: 65)]),
                ),
            ),    

            Positioned(top: 250,left: 17.5,
                child: Container(
                  padding: EdgeInsets.only(
                    top: 40,
                    left: 20,
                    right: 20,),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        "Sign in / Login",
                        style:TextStyle(
                          color: Color.fromARGB(255, 132, 92, 202),
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                        ),
                      ),
                  SizedBox(height: 20,),
                      Text(
                        "Email",
                        style: TextStyle(
                          fontSize: 25,
                          color: Color.fromARGB(255, 160, 123, 225),
                        ),
                      ),
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Enter your Email",
                        filled: true,
                        fillColor: Color.fromARGB(255, 160, 123, 225),
                        border: OutlineInputBorder(),
                    ),
                   ),
                  SizedBox(height:35,),
                   Text(
                    "Mot de passe",
                    style: TextStyle(
                      fontSize: 25,
                      color: Color.fromARGB(255, 160, 123, 225),
                    ),
                   ),
                   TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: "Enter your password",
                      filled: true,
                      fillColor: Color.fromARGB(255, 160, 123, 225),
                      border: OutlineInputBorder(),
                    ),
                   ),
                   SizedBox(height:20,),
                   Align(
                    alignment: Alignment.topCenter,
                   
                   child: Text(
                    "Or with",
                    style: TextStyle(
                      fontSize: 20,
                      color: Color.fromARGB(255, 160, 123, 225),
                    ),
                   ),
                   ),
                    ],
                  ),
                  width:375,
                  height:450,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    color: Color.fromARGB(149, 87, 37, 141),
                    borderRadius: BorderRadius.circular(20)),
                    
                  ),
                ),
            
                Align(
                alignment: Alignment(0, -0.7),
                  child: Text(
                  "Welcome",
                    style: TextStyle(
                      fontSize: 37,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 170, 137, 227),
                    ),
                  ),
              ),
            ],
        ),
      ),
    );
}
}
