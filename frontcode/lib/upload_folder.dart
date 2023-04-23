import 'dart:typed_data';
import 'dart:convert';

import 'package:ic_tools/ic_tools.dart';
import 'package:ic_tools/candid.dart';
import 'package:collection/collection.dart';
import 'package:archive/archive.dart';



Future<void> upload_files({
    required List<FileUpload> files,
    required Canister file_server_canister,
    required Caller caller,
    required List<Legation> legations,
    required String upload_file_method_name,
    required String upload_file_chunk_method_name,
    void Function(int, String)? do_for_each_filename = null,
}) async {

    //List<Future> upload_files_futures = [];
    
    GZipEncoder gzip = GZipEncoder();
    
    for (int i = 0; i<files.length; i++) {
        
        FileUpload f = files[i];
        
        if (do_for_each_filename != null) {
            do_for_each_filename(i, f.name);
        }
        
        //upload_files_futures.add(Future(()async{
        await Future(()async{
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
                    //upload_chunks_futures.add(Future(()async{
                    await Future(()async{
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
                    });
                    //}));
                }
                //await Future.wait(upload_chunks_futures);
            }
        });
        //}));
    }
    //await Future.wait(upload_files_futures);
}







class FileUpload {
    final String name;
    final String path;
    final int size;
    final String content_type; // mime-type
    final Uint8List bytes;
    FileUpload({
        required this.name,
        required this.path,
        required this.size,
        required this.content_type, // mime-type
        required this.bytes,
    }) {
        if (size != bytes.length) { throw Exception('file: ${name} bytes length != size. bytes_length: ${bytes.length}, size: $size'); }
    }
        
}


