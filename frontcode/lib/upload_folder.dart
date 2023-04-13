


Future<void> upload_files({
    required List<FileUpload> files,
    required Canister file_server_canister,
    required Caller caller,
    required List<Legation> legations
}) async {

    List<Future> upload_files_futures = [];
    
    for (FileUpload f in files) {
        
        upload_files_futures.add(Future(()async{
                
            List<int> file_bytes = gzip.encode(await f.bytes);
            Iterable<List<int>> file_bytes_chunks = file_bytes.slices(1024*1024 + 1024*512);

            List<CandidType> cs = c_backwards(await file_server_canister.call(
                calltype: CallType.call,
                method_name: 'user_upload_file',
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
                        List<CandidType> cschunk = c_backwards(await file_server_canister.call(
                            calltype: CallType.call,
                            method_name: 'user_upload_file_chunks',
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
                    }));
                }
                await Future.wait(upload_chunks_futures);
            }
        }));
    }
    await Future.wait(upload_files_futures);
}



