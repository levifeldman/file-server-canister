import 'dart:typed_data';
import 'dart:math';
import 'dart:indexed_db';
import 'dart:html';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/tools.dart';
import 'package:ic_tools/candid.dart';
import 'package:ic_tools_web/ic_tools_web.dart' as ic_tools_web;
import 'package:ic_tools_web/ic_tools_web.dart' show NullMap;

class CustomState {
    
    static Canister main_canister = Canister(Principal('qiylj-niaaa-aaaai-qaiea-cai'));     
    
    User? user;
    
    bool loading = false;

    Future<void> load_first_state() async {
        if (this.user == null) {
            this.user = (await ic_tools_web.User.load_user_of_the_indexdb()).nullmap(User.of_an_ic_tools_web_user);
        }
        if (this.user != null) {
            await Future.wait([
                this.user!.load_user_temporary_server_filepaths(),
                Future(()async{
                    await this.user!.load_user_server();
                    if (this.user!.user_server != null) {
                        await this.user!.user_server!.load_filepaths();
                    }
                }),
            ]);
        }
        
    }

    

}

class User extends ic_tools_web.User {
    
    static User of_an_ic_tools_web_user(ic_tools_web.User u) => User(caller: u.caller, legations: u.legations);
    
    User({required super.caller, required super.legations});
    
    List<String> user_temporary_server_filepaths = [];
    UserServer? user_server;
    
    Future<void> load_user_temporary_server_filepaths() async {
        this.user_temporary_server_filepaths = (c_backwards(await call(
            CustomState.main_canister,
            method_name: 'see_user_temporary_server_filepaths',
            calltype: CallType.query,
            put_bytes: c_forwards([])
        )).first as Vector).cast_vector<Text>().map<String>((t)=>t.value).toList();
    }

    Future<void> load_user_server() async {
        this.user_server = (c_backwards(await call(
            CustomState.main_canister,
            method_name: 'see_user_server_canister_id',
            calltype: CallType.query,
            put_bytes: c_forwards([])
        )).first as Option).cast_option<Principal>().value.nullmap((p)=>UserServer(user: this, canister: Canister(p)));
    }
    
    Future<void> delete_user_temporary_server_files() async {
        await call(
            CustomState.main_canister,
            method_name: 'delete_user_temporary_server_files',
            calltype: CallType.call,
            put_bytes: c_forwards([])
        );
    }

}

class UserServer {
    User user;
    Canister canister;
    List<String> filepaths = [];
    
    UserServer({required this.user, required this.canister});
    
    Future<void> load_filepaths() async {
        this.filepaths = (c_backwards(await user.call(
            this.canister,
            method_name: 'see_filepaths',
            calltype: CallType.query,
            put_bytes: c_forwards([])
        )).first as Vector).cast_vector<Text>().map<String>((t)=>t.value).toList();
    }

}
