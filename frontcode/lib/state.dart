import 'dart:typed_data';
import 'dart:math';
import 'dart:indexed_db';
import 'dart:html';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/tools.dart';
import 'package:ic_tools_web/ic_tools_web.dart';


class CustomState {

    User? user;
    
    bool loading = false;

    Future<void> load_first_state() async {
        this.user = await User.load_user_of_the_indexdb();
        // check user data in the canister
        
    }

    

}


