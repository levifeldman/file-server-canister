
use ic_cdk::{
    export::{
        candid::{
            CandidType,
            Deserialize,
            encode_one,
            decode_one
        }
    },
    api::{
        stable::{
            WASM_PAGE_SIZE_IN_BYTES as WASM_PAGE_SIZE_BYTES,
            stable64_size,
            stable64_read,
            stable64_write,
            stable64_grow
        }
    },
    trap,
};


use crate::{
    tools::{
        localkey::{
            refcell::{
                with_mut
            }
        }
    },
    data::{
        FILES,
        FILES_HASHES,
    },
    types::{
        FilesHashes,
        Files
    },
    tools::{
        set_root_hash
    }
};






pub const STABLE_MEMORY_HEADER_SIZE_BYTES: u64 = 1024;






#[derive(CandidType, Deserialize)]
struct FileServerData {
    files: Files,
    files_hashes: Vec<(String, [u8; 32])>,
}



pub fn pre_upgrade<CanisterData: CandidType + for<'a> Deserialize<'a>>(canister_data: CanisterData) {
    
    let file_server_data: FileServerData = FileServerData{
        files: with_mut(&FILES, |files| { std::mem::take(files) }),
        files_hashes: with_mut(&FILES_HASHES, |files_hashes| { std::mem::take(files_hashes) }) 
            .iter()
            .map(|(name, hash)| { (name.clone(), hash.clone()) }
            ).collect::<Vec<(String, [u8; 32])>>(),
    }; 
    
    let file_server_data_candid_bytes: Vec<u8> = encode_one(&file_server_data).unwrap();
    let file_server_data_candid_bytes_len_u64: u64 = file_server_data_candid_bytes.len() as u64;
    
    let canister_data_candid_bytes: Vec<u8> = encode_one(&canister_data).unwrap();
    let canister_data_candid_bytes_len_u64: u64 = canister_data_candid_bytes.len() as u64;
        
        
    // ---
    
    let current_stable_size_wasm_pages: u64 = stable64_size();
    let current_stable_size_bytes: u64 = current_stable_size_wasm_pages * WASM_PAGE_SIZE_BYTES as u64;

    let want_stable_memory_size_bytes: u64 = 
        STABLE_MEMORY_HEADER_SIZE_BYTES 
        + 8/*len of the file_server_data_candid_bytes*/ 
        + file_server_data_candid_bytes_len_u64
        + 8/*len of the canister_data_candid_bytes*/
        + canister_data_candid_bytes_len_u64;
    
    if current_stable_size_bytes < want_stable_memory_size_bytes {
        stable64_grow(((want_stable_memory_size_bytes - current_stable_size_bytes) / WASM_PAGE_SIZE_BYTES as u64) + 1).unwrap();
    }
    
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES, &(file_server_data_candid_bytes_len_u64.to_be_bytes()));
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES + 8, &file_server_data_candid_bytes);
    
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES + 8 + file_server_data_candid_bytes_len_u64, &(canister_data_candid_bytes_len_u64.to_be_bytes()));
    stable64_write(STABLE_MEMORY_HEADER_SIZE_BYTES + 8 + file_server_data_candid_bytes_len_u64 + 8, &canister_data_candid_bytes);

}

pub fn post_upgrade<OldCanisterData, CanisterData, F>(opt_old_to_new_convert: Option<F>) -> CanisterData 
    where 
        OldCanisterData: CandidType + for<'a> Deserialize<'a>,
        CanisterData: CandidType + for<'a> Deserialize<'a>,
        F: FnOnce(OldCanisterData) -> CanisterData
    {


    let file_server_data_candid_bytes_len_u64: u64 = read_u64_at_position(STABLE_MEMORY_HEADER_SIZE_BYTES); 
    let file_server_data_candid_bytes: Vec<u8> = read_bytes_at_position_for_length(
        STABLE_MEMORY_HEADER_SIZE_BYTES + 8, 
        file_server_data_candid_bytes_len_u64
    );

    let canister_data_candid_bytes_len_u64: u64 = read_u64_at_position(STABLE_MEMORY_HEADER_SIZE_BYTES + 8 + file_server_data_candid_bytes_len_u64); 
    let canister_data_candid_bytes: Vec<u8> = read_bytes_at_position_for_length(
        STABLE_MEMORY_HEADER_SIZE_BYTES + 8 + file_server_data_candid_bytes_len_u64 + 8,
        canister_data_candid_bytes_len_u64
    );
    // ---
    
    let mut file_server_data: FileServerData = match decode_one::<FileServerData>(&file_server_data_candid_bytes) {
        Ok(data) => data,
        Err(e) => {
            trap(&format!("error decode of the FileServerData: {:?}", e));
            /*
            let old_file_server_data: OldFileServerData = decode_one::<OldFileServerData>(&file_server_data_candid_bytes).unwrap();
            let file_server_data: FileServerData = FileServerData{
                files: old_file_server_data.files,
                files_hashes: old_file_server_data.files_hashes,
                ...
            };
            file_server_data
            */    
        }
    };

    with_mut(&FILES, |files| {
        *files = file_server_data.files;    
    });

    with_mut(&FILES_HASHES, |files_hashes| {
        *files_hashes = FilesHashes::from_iter(file_server_data.files_hashes.drain(..));
        set_root_hash(files_hashes);
    });
    
    let canister_data: CanisterData = match decode_one::<CanisterData>(&canister_data_candid_bytes) {
        Ok(data) => data,
        Err(e) => match opt_old_to_new_convert {
            None => trap(&format!("error decode of the canister_data: {:?}", e)),
            Some(old_to_new_convert) => {
                let old_canister_data: OldCanisterData = decode_one::<OldCanisterData>(&canister_data_candid_bytes).unwrap();
                let canister_data: CanisterData = old_to_new_convert(old_canister_data);
                canister_data
            }    
        }
    };
    
    canister_data
}







fn read_u64_at_position(position: u64) -> u64 {
    let mut u64_be_bytes: [u8; 8] = [0; 8];
    stable64_read(position, &mut u64_be_bytes);
    u64::from_be_bytes(u64_be_bytes)
}

fn read_bytes_at_position_for_length(position: u64, length: u64) -> Vec<u8> {
    let mut bytes: Vec<u8> = vec![0; length as usize];
    stable64_read(position, &mut bytes);
    bytes
}


