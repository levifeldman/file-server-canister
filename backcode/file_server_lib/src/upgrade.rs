






pub const STABLE_MEMORY_HEADER_SIZE_BYTES: u64 = 1024;



pub fn pre_upgrade<T: CandidType + Deserialize, F: FnOnce()>(canister_data: T) {
    
    with_mut(&FILE_SERVER_DATA, |file_server_data| {
        file_server_data.files_hashes = with(&FILES_HASHES, |files_hashes| { 
            files_hashes.iter().map(
                |(name, hash)| { (name.clone(), hash.clone()) }
            ).collect::<Vec<(String, [u8; 32])>>() 
        });
        file_server_data.canister_data = Some(canister_data);
    });
    
    let file_server_data_candid_bytes: Vec<u8> = with(&FILE_SERVER_DATA, |file_server_data| { encode_one(file_server_data).unwrap() });
        
    // ---
    
    let current_stable_size_wasm_pages: u64 = stable64_size();
    let current_stable_size_bytes: u64 = current_stable_size_wasm_pages * WASM_PAGE_SIZE_BYTES as u64;


    let want_stable_memory_size_bytes: u64 = STABLE_MEMORY_HEADER_SIZE_BYTES + 8/*len of the file_server_data_candid_bytes*/ + file_server_data_candid_bytes.len() as u64; 
    if current_stable_size_bytes < want_stable_memory_size_bytes {
        stable64_grow(((want_stable_memory_size_bytes - current_stable_size_bytes) / WASM_PAGE_SIZE_BYTES as u64) + 1).unwrap();
    }
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES, &((file_server_data_candid_bytes.len() as u64).to_be_bytes()));
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES + 8, file_server_data_candid_bytes);

}

pub fn post_upgrade<OldCanisterData, CanisterData, F>(opt_old_to_new_convert: Option<F>) -> CanisterData 
    where 
        OldCanisterData: CandidType + Deserialize,
        CanisterData: CandidType + Deserialize,
        F: FnOnce(OldCanisterData) -> CanisterData
    {
    

    let mut state_snapshot_len_u64_be_bytes: [u8; 8] = [0; 8];
    stable64_read(STABLE_MEMORY_HEADER_SIZE_BYTES, &mut state_snapshot_len_u64_be_bytes);
    let state_snapshot_len_u64: u64 = u64::from_be_bytes(state_snapshot_len_u64_be_bytes); 
    
    let mut file_server_data_candid_bytes: Vec<u8> = vec![0; state_snapshot_len_u64 as usize];
    stable64_read(STABLE_MEMORY_HEADER_SIZE_BYTES + 8, file_server_data_candid_bytes);
    let file_server_data_candid_bytes: Vec<u8> = file_server_data_candid_bytes; // cancel mut
    
    // ---
    
    let mut file_server_data_of_the_state_snapshot: FileServerData<CanisterData> = {
        match decode_one::<FileServerData<CanisterData>>(file_server_data_candid_bytes) {
            Ok(file_server_data) => file_server_data,
            Err(e) => match opt_old_to_new_convert {
                None => trap(&format!("error decode of the canister data: {:?}", e)),
                Some(old_to_new_convert) => {
                    let file_server_data_with_old_canister_data: FileServerData<OldCanisterData> = decode_one::<FileServerData<OldCanisterData>>(file_server_data_candid_bytes).unwrap();
                    let file_server_data_with_new_canister_data: FileServerData<CanisterData> = {
                        FileServerData<CanisterData>{
                            files: file_server_data_with_old_canister_data.files,
                            files_hashes: file_server_data_with_old_canister_data.files_hashes,
                            canister_data: Some(old_to_new_convert(file_server_data_with_old_canister_data.canister_data.unwrap())) 
                        }
                    };
                    file_server_data_with_new_canister_data    
                }    
            }
        }
    };

    with_mut(&FILES_HASHES, |files_hashes| {
        *files_hashes = FilesHashes::from_iter(file_server_data_of_the_state_snapshot.files_hashes.drain(..));
        set_root_hash(files_hashes);
    });

    let canister_data: CanisterData = file_server_data_of_the_state_snapshot.canister_data.take().unwrap();

    with_mut(&FILE_SERVER_DATA, |file_server_data| {
        *file_server_data = file_server_data_of_the_state_snapshot;    
    });
    
    canister_data
}



