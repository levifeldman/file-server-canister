import 'dart:typed_data';
import 'dart:math';
import 'dart:indexed_db';
import 'dart:html';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/tools.dart';
import 'package:ic_tools/candid.dart';
import 'package:ic_tools/common.dart';
import 'package:ic_tools_web/ic_tools_web.dart' as ic_tools_web;
import 'package:ic_tools_web/ic_tools_web.dart' show NullMap;
import 'package:tuple/tuple.dart';

import './files_and_directories.dart';



final IcpTokens CREATE_SERVER_MINIMUM_ICP = IcpTokens.oftheDoubleString('0.5');

final Canister main_canister = Canister(Principal('z7kqr-4yaaa-aaaaj-qaa5q-cai'));

class CustomState {
    
    User? user;
    
    bool loading = false;

    Future<void> load_first_state() async {
        /*
        String LOCAL = String.fromEnvironment('LOCAL'); 
        if (LOCAL != 'true' && LOCAL != 'false') {
            throw Exception('environment variable \'LOCAL\' must be set to \'true\' or \'false\'');
        }
        if (LOCAL == 'true') {
            icbaseurl = Uri.parse('http://127.0.0.1:4943');
            Map ic_status_map = await ic_status();
            icrootkey = Uint8List.fromList(ic_status_map['root_key']!);   
        }
        try {
            main_canister = Canister(Principal(String.fromEnvironment('MAIN_CANISTER'))); // z7kqr-4yaaa-aaaaj-qaa5q-cai        
        } catch(e) {
            throw Exception('MAIN_CANISTER environment variable must be a valid Principal\n${e}');
        }
        */
        
        // -----
    
        if (this.user == null) {
            this.user = (await ic_tools_web.User.load_user_of_the_indexdb()).nullmap(User.of_an_ic_tools_web_user);
        }
        if (this.user != null) {
            await Future.wait([
                this.user!.load_file_server_main_user_subaccount_icp_balance(),
                Future(()async{
                    await this.user!.load_user_servers();
                    await Future.wait(this.user!.user_servers.map<Future<void>>((user_server)=>user_server.load_filepaths()));
                }),
            ]);
        }
        
    }

    

}

class User extends ic_tools_web.User {
    
    static User of_an_ic_tools_web_user(ic_tools_web.User u) => User(caller: u.caller, legations: u.legations);
    
    User({required super.caller, required super.legations});
    
    String get file_server_main_user_subaccount_icp_id => icp_id(main_canister.principal, subaccount_bytes: principal_as_an_icpsubaccountbytes(this.principal));
    
    IcpTokens file_server_main_user_subaccount_icp_balance = IcpTokens(e8s: BigInt.from(0));
    
    List<UserServer> user_servers = [];


    Future<void> load_file_server_main_user_subaccount_icp_balance() async {
        this.file_server_main_user_subaccount_icp_balance = await check_icp_balance(
            this.file_server_main_user_subaccount_icp_id, 
            calltype: CallType.query
        );
    }

    Future<void> load_user_servers() async {
        this.user_servers = (c_backwards(await call(
            main_canister,
            method_name: 'see_user_server_canister_ids',
            calltype: CallType.query,
            put_bytes: c_forwards([])
        )).first as Vector).cast_vector<PrincipalReference>().map((pr)=>UserServer(user: this, canister: Canister(pr.principal!))).toList();
    }
    
    
    Future<UserServer> create_server(IcpTokens with_icp) async {
        if (with_icp < CREATE_SERVER_MINIMUM_ICP) {
            throw Exception('Create server minimum icp: $CREATE_SERVER_MINIMUM_ICP');
        }
        await this.load_file_server_main_user_subaccount_icp_balance();
        if (this.file_server_main_user_subaccount_icp_balance < with_icp) {
            throw Exception('Current user icp balance is ${this.file_server_main_user_subaccount_icp_balance}\nSelect an icp amount within the balance. ');
        }
        Variant create_server_result = c_backwards(
            await call(
                main_canister,
                calltype: CallType.call,
                method_name: 'user_create_server',
                put_bytes: c_forwards([
                    Record.oftheMap({
                        'with_icp': with_icp
                    })
                ])
            )
        )[0] as Variant;
        return await match_variant<Future<UserServer>>(create_server_result, create_server_result_match_map);   
    }
    
    Future<UserServer> continue_create_server() async {
        Variant continue_create_server_result = c_backwards(
            await call(
                main_canister,
                calltype: CallType.call,
                method_name: 'continue_user_create_server',
                put_bytes: c_forwards([])
            )
        )[0] as Variant;
        return await match_variant<Future<UserServer>>(continue_create_server_result, continue_create_server_result_match_map);
    }
    
    Map<String, Future<UserServer> Function(CandidType)> get create_server_result_match_map => {
        Ok: (create_server_success_ctype) async {
            Record create_server_success = create_server_success_ctype as Record;
            UserServer user_server = UserServer(
                user: this,
                canister: Canister(create_server_success['server_canister_id'] as Principal)
            );
            this.user_servers.add(user_server);
            return user_server;
        },
        Err: (create_server_error) async {
            return await match_variant<Future<UserServer>>(create_server_error as Variant, create_server_error_match_map);
        }  
    };
    
    Map<String, Future<UserServer> Function(CandidType)> get continue_create_server_result_match_map => {
        Ok: (create_server_success_ctype) async {
            return await create_server_result_match_map[Ok]!(create_server_success_ctype);    
        },
        Err: (continue_create_server_error) async {
            return await match_variant<Future<UserServer>>(continue_create_server_error as Variant, continue_create_server_error_match_map);
        }
    };
    
    Map<String, Future<UserServer> Function(CandidType)> get create_server_error_match_map => {
        'MidCallError': (mid_call_error) async {
            print('user_create_server mid_call_error: ${mid_call_error}');
            return await this.continue_create_server();          
        },
        'CreateServerMinimumIcp': (icp_tokens_ctype) async {
            throw Exception('CreateServerMinimumIcp: ${IcpTokens.oftheRecord(icp_tokens_ctype)}');
        },
        'UserIsInTheMiddleOfADifferentCall': (user_is_in_the_middle_of_a_different_call) async {
            print('UserIsInTheMiddleOfADifferentCall: $user_is_in_the_middle_of_a_different_call');
            match_variant<Never>((user_is_in_the_middle_of_a_different_call as Record)['kind'] as Variant, {
                'UserCreateServer': (null_ctype) {
                    if (((user_is_in_the_middle_of_a_different_call as Record)['must_call_continue'] as Bool).value == true) {
                        continue_create_server()
                        .then((user_server){
                            window.alert('user_create_server is complete.\nserver-id: ${user_server.canister.principal.text}');
                        }).catchError((e){
                            window.alert('user_create_server error: \n${e}');
                        });
                    }
                    throw Exception('user is in the middle of a different user_create_server call.');
                }
            });
        },
        'Busy': (null_ctype) async {
            throw Exception('Canister is busy, try soon.');
        },
        'TopUpCyclesLedgerTransferError': (topup_cycles_ledger_transfer_error) async {
            match_variant<Never>(topup_cycles_ledger_transfer_error as Variant, {
                'IcpTransferCallError': (call_error) {
                    throw Exception('IcpTransferCallError: \n${CallException(
                        reject_code: ((call_error as Record)[0] as Nat32).value,
                        reject_message: ((call_error as Record)[1] as Text).value,
                    )}');
                },
                'IcpTransferError': (icp_transfer_error) {
                    match_variant<Never>(icp_transfer_error as Variant, icp_transfer_error_match_map);
                },
            });
        },
    };
    
    Map<String, Future<UserServer> Function(CandidType)> get continue_create_server_error_match_map => {
        'CallerIsNotInTheMiddleOfAUserCreateServerCall': (n) async {
            throw Exception('user is not in the middle of a user_create_server call.');
        },
        'UserCreateServerError': (create_server_error_ctype) async {
            return await match_variant<Future<UserServer>>(create_server_error_ctype as Variant, create_server_error_match_map);
        }
    };

    
    


}





class UserServer {
    User user;
    Canister canister;
    List<String> filepaths = [];
    
    UserServer({required this.user, required this.canister});
    
    String get link => 'https://${this.canister.principal}.icp0.io';
    
    Future<void> load_filepaths() async {
        this.filepaths = (c_backwards(await user.call(
            this.canister,
            method_name: 'see_filepaths',
            calltype: CallType.query,
            put_bytes: c_forwards([])
        )).first as Vector).cast_vector<Text>().map<String>((t)=>t.value).toList();
    }
    
    Future<void> clear_files() async {
        await user.call(
            this.canister,
            method_name: 'user_clear_files',
            calltype: CallType.call,
            put_bytes: c_forwards([])
        );
    }
    
    Directory get directory {
        Tuple2<List<File>, List<Directory>> files_and_folders = 
        files_and_folders_of_the_filepaths(this.filepaths);
        return Directory(
            path: '/',
            files: files_and_folders.item1,
            folders: files_and_folders.item2
        );
    }
    

    
    @override
    bool operator ==(/*covariant UserServer*/ other) => other is UserServer && other.canister == this.canister;

    @override
    int get hashCode => this.canister.hashCode;    
    

}




Uint8List principal_as_an_icpsubaccountbytes(Principal principal) {
    List<int> bytes = []; // an icp subaccount is 32 bytes
    bytes.add(principal.bytes.length);
    bytes.addAll(principal.bytes);
    while (bytes.length < 32) { bytes.add(0); }
    return Uint8List.fromList(bytes);
}




Map<String, Never Function(CandidType)> icp_transfer_error_match_map = {
    'TxTooOld' : (allowed_window_nanos_r) {
        throw Exception('TxTooOld');
    },
    'BadFee' : (expected_fee_r) {
        throw Exception('BadFee, expected_fee: ${IcpTokens.oftheRecord((expected_fee_r as Record)['expected_fee'] as Record)}');
    },
    'TxDuplicate' : (duplicate_of_r) {
        throw Exception('TxDuplicate, duplicate_of: ${((duplicate_of_r as Record)['duplicate_of'] as Nat64).value}');
    },
    'TxCreatedInFuture': (nul) {
        throw Exception('TxCreatedInFuture');
    },
    'InsufficientFunds' : (balance_r) {
        throw Exception('InsufficientFunds, balance: ${IcpTokens.oftheRecord((balance_r as Record)['balance'] as Record)}');
    }
};





