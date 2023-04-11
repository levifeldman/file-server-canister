import 'dart:typed_data';
import 'dart:math';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools_web/ic_tools_web.dart';

class CustomState {

    User? user;
    
    bool loading = false;

    Future<void> load_first_state() async {
        // check indexdb for a current user and legations (unexpired) 
    }


}



class User {
    final SubtleCryptoECDSAP256Caller caller;
    final List<Legation> legations;
    
    User({
        required this.caller,
        required this.legations,
    });
    
    BigInt? get expiration_unix_timestamp_nanoseconds => this.legations.isNotEmpty ? this.legations.map((l)=>l.expiration_unix_timestamp_nanoseconds).toList().reduce((current, next) => current <= next ? current : next) : null;
    Uint8List get public_key_DER => legations.length >= 1 ? legations[0].legator_public_key_DER : caller.public_key_DER;
    Principal get principal => Principal.ofthePublicKeyDER(this.public_key_DER);
    
    Future<Uint8List> call(Canister canister, {required CallType calltype, required String method_name, Uint8List? put_bytes, Duration timeout_duration = const Duration(minutes: 10)}) {
        return canister.call(caller:this.caller, legations:this.legations, calltype:calltype, method_name:method_name, put_bytes:put_bytes, timeout_duration:timeout_duration);
    }
    
    static Future<User> login() async {
        SubtleCryptoECDSAP256Caller legatee_caller = await SubtleCryptoECDSAP256Caller.new_keys();
        List<Legation> legations = await ii_login(
            legatee_caller,
            valid_duration: Duration(days: 30),
        );
        // save user in the indexdb
        return User(
            caller: legatee_caller,
            legations: legations
        );
    }
    
}
