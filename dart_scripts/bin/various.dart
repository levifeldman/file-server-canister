import 'dart:typed_data';
import 'dart:io';


import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/candid.dart';
import 'package:ic_tools/common.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:archive/archive.dart';



import '../../frontcode/lib/upload_folder.dart' show FileUpload;


Future<void> main(List<String> arguments) async {
    
    Canister file_server_main = Canister(Principal('z7kqr-4yaaa-aaaaj-qaa5q-cai'));
    
    String controller_json_path = 'controller.json';
    
    File controller_json_file = File(controller_json_path);
    
    late CallerEd25519 controller;
    
    if (await controller_json_file.exists()) {
        Map controller_json = jsonDecode(utf8.decode(await controller_json_file.readAsBytes()));
        controller = CallerEd25519(
            public_key: Uint8List.fromList(controller_json['controller']!['public_key']!.cast<int>()),
            private_key: Uint8List.fromList(controller_json['controller']!['private_key']!.cast<int>())
        );
    } else {
        controller = CallerEd25519.new_keys();
        await controller_json_file.writeAsString(jsonEncode({
            'controller': {
                'public_key': controller.public_key.toList(),
                'private_key': controller.private_key.toList()
            }
        }));
        print('creating new ed25519 keys: ${controller.principal.text}\nsaving keys in ${controller_json_path}');
    }
    
    
    print('using controller: ${controller.principal.text}'); 

    
    if (arguments[0] == 'check_canister_status') {
        print(await check_canister_status(controller, file_server_main.principal));
    }
    else if (arguments[0] == 'install_code') {
        String mode = arguments[1];
        await put_code_on_the_canister(
            controller,
            file_server_main.principal,
            File('../backcode/target/wasm32-unknown-unknown/release/main_canister.wasm').readAsBytesSync(),
            mode,
            c_forwards([
                Record.oftheMap({
                    'controllers': Vector.oftheList<Principal>([
                        controller.principal
                    ])
                })
            ])
        );
    } else if (arguments[0] == 'uninstall_code') {
        print(c_backwards(await SYSTEM_CANISTERS.management.call(
            calltype: CallType.call,
            method_name: 'uninstall_code',
            caller: controller,
            put_bytes: c_forwards([
                Record.oftheMap({
                    'canister_id': file_server_main.principal
                })
            ])
        )));
    } else if (arguments[0] == 'controller_upload_user_server_code') {
        Uint8List user_canister_module = File('../backcode/target/wasm32-unknown-unknown/release/user_canister.wasm').readAsBytesSync();
        print(c_backwards(await file_server_main.call(
            calltype: CallType.call,
            method_name: 'controller_upload_user_server_code',
            caller: controller,
            put_bytes: c_forwards([
                Record.oftheMap({
                    'module': Blob(user_canister_module),
                    'hash': Blob(sha256.convert(user_canister_module).bytes)
                })
            ])
        )));
    }
    else if (arguments[0] == 'upload_frontcode') {
        List<FileUpload> file_uploads= [];
        String build_web_dir_string = '../frontcode/build/web';
        
        await for (FileSystemEntity fse in Directory(build_web_dir_string).list(recursive: true, followLinks: false)) {
            if (fse is File) {                
                String path = fse.path.replaceFirst(build_web_dir_string, '');
                if (path == '/index.html') {
                    path = '/';
                }
                
                String content_type = '';
                if (path.length >= 5 && path.substring(path.length-5) == '.wasm') { content_type = 'application/wasm'; }
            
                Uint8List bytes = await (fse as File).readAsBytes();
                
                file_uploads.add(FileUpload(
                    name: '',
                    path: path,
                    size: bytes.length,
                    content_type: content_type,
                    bytes:bytes
                ));
            }
        }
        
        await upload_files(
            files: file_uploads, 
            file_server_canister: file_server_main, 
            caller: controller, 
            legations: [],
            upload_file_method_name: 'controller_upload_file',
            upload_file_chunk_method_name: 'controller_upload_file_chunk',
        );
    }
    else if (arguments[0] == 'clear_frontcode') {
        print(c_backwards(await file_server_main.call(
            calltype: CallType.call,
            method_name: 'controller_clear_files',
            caller: controller,
            put_bytes: c_forwards([])
        )));
    } else {
        throw Exception('command: ${arguments[0]} not found');
    }

}





Future<void> upload_files({
    required List<FileUpload> files,
    required Canister file_server_canister,
    required Caller caller,
    required List<Legation> legations,
    required String upload_file_method_name,
    required String upload_file_chunk_method_name,
    void Function(int, String)? do_for_each_filename = null,
}) async {

    List<Future> upload_files_futures = [];
    
    GZipEncoder gzip = GZipEncoder();
    
    for (int i = 0; i<files.length; i++) {
        
        FileUpload f = files[i];
        
        if (do_for_each_filename != null) {
            do_for_each_filename(i, f.name);
        }
        
        upload_files_futures.add(Future(()async{
        //await Future(()async{
            List<int> file_bytes = gzip.encode(f.bytes)!;
            Iterable<List<int>> file_bytes_chunks = file_bytes.slices(1024*1024 + 1024*512);

            List<CandidType> cs = c_backwards(await file_server_canister.call(
                calltype: CallType.call,
                method_name: upload_file_method_name,
                caller: caller,
                legations: legations,
                put_bytes: c_forwards([
                    Record.oftheMap({
                        'path': Text(f.path),
                        'first_chunk': Blob(file_bytes_chunks.first),
                        'chunks': Nat32(file_bytes_chunks.length),
                        'headers': Vector.oftheList<Record>([
                            Record.oftheMap({0: Text('Content-Type'), 1: Text(f.content_type)}),
                            Record.oftheMap({0: Text('Content-Encoding'), 1: Text('gzip')}),                            
                            Record.oftheMap({0: Text("Access-Control-Allow-Origin"), 1: Text("*")}),
                        ]),
                    }),
                ])
            ));
            print('${f.path}: $cs');
            
            if (file_bytes_chunks.length > 1) {
                List<Future> upload_chunks_futures = [];
                for (int i = 1; i<file_bytes_chunks.length; i++) {
                    upload_chunks_futures.add(Future(()async{
                    //await Future(()async{
                        List<CandidType> cschunk = c_backwards(await file_server_canister.call(
                            calltype: CallType.call,
                            method_name: upload_file_chunk_method_name,
                            caller: caller,
                            legations: legations,
                            put_bytes: c_forwards([
                                Record.oftheMap({
                                    'path': Text(f.path),
                                    'chunk_i': Nat32(i),
                                    'chunk': Blob(file_bytes_chunks.elementAt(i)), 
                                })
                            ])
                        ));
                        print('${f.path} : $i -> $cschunk');
                    //});
                    }));
                }
                await Future.wait(upload_chunks_futures);
            }
        //});
        }));
    }
    await Future.wait(upload_files_futures);
}


